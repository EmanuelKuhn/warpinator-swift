//
//  Remote.swift
//  warpinator-project
//
//  Created by Emanuel on 13/02/2022.
//

import Foundation
import Sodium
import GRPC

import NIO

import Combine

enum RemoteError: String, Error {
    case clientNotInitialized
    
    case peerMissingFetchCertInfo
    
    case failedToResolvePeer
    
    case failedToFetchLockedCertificate
    case failedToUnlockCertificate
    
    case failedToMakeWarpClient
}

class Remote: ObservableObject {
    
    private let statemachine: StateMachine
    private var stateCancellable: AnyCancellable?

    @Published var state: RemoteState {
        willSet { /* Leave state */ }
        didSet {
            DispatchQueue.global().async {
                Task {
                    await self.enterState(self.state)
                }
            }
        }
      }  
    
    var peer: Peer

    let id: String
    
    private let auth: Auth
    
    private var certificate: Bytes? = nil
    private var connection: RemoteConnection?
    
    
    var displayName: String? = nil
    var userName: String? = nil
    
    private var client: WarpAsyncClient? {
        get {
            return connection?.client
        }
    }
    
    func deinitClient() {
        connection = nil
    }
    
    var transfers: CurrentValueSubject<Array<TransferOp>, Never> = .init([])
    
    var transfersToRemote: Dictionary<UInt64, TransferToRemote> = .init() {
        willSet {
            
            var merged: [TransferOp] = Array(newValue.values)
            merged.append(contentsOf: Array(transfersFromRemote.values))
            
            merged.sort { $0.localTimestamp > $1.localTimestamp }
            
            transfers.value = merged
        }
    }
    
    var transfersFromRemote: Dictionary<UInt64, TransferFromRemote> = .init() {
        willSet {
            
            var merged: [TransferOp] = Array(newValue.values)
            merged.append(contentsOf: Array(transfersToRemote.values))
            
            merged.sort { $0.localTimestamp > $1.localTimestamp }
            
            transfers.value = merged
        }
    }
    
    func transferOps(forKey timestamp: UInt64) -> [TransferOp] {
        var transferOps: [TransferOp] = []
        
        if let transferOp = transfersToRemote[timestamp] {
            transferOps.append(transferOp)
        }
        
        if let transferOp = transfersFromRemote[timestamp] {
            transferOps.append(transferOp)
        }
        
        return transferOps
    }
    
    let eventLoopGroup: EventLoopGroup
        
    func enterState(_ state: RemoteState) async {
        switch state {
        case .fetchingCertificate, .retrying:
            do {
                try await createConnection()

                let pingResult = await ping()
                
                print("\n\nPing result: \(pingResult)")
                
                // GRPC channel only tries to connect when the first call happens
                try await waitingForDuplex()
                
                await statemachine.tryEvent(.gotDuplex)
            } catch {

                print("\n\nError while in .mdnsDiscovered case; error (\(error.self)): \(error)\n\n")
            }

        case .offline:
            return
//            deinitClient()
        case .waitingForDuplex:
            return
        case .online:
            try? await getRemoteMachineInfo()
        case .channelTransientFailure:
            return
        case .channelShutdownFailure:
            return
        case .unExpectedTransition:
            return
        }
    }
    
    init(id: String, peer: Peer, auth: Auth, eventLoopGroup: EventLoopGroup) {
        self.id = id
        self.auth = auth
        
        self.eventLoopGroup = eventLoopGroup
        
        self.peer = peer
        
        self.statemachine = StateMachine()
        
        self.state = statemachine.state
        
        self.stateCancellable = statemachine.statePublisher.sink { [weak self] state in
            self?.state = state
        }
        
        Task {
            await self.mdnsDiscovered(peer: peer)
        }
    }
    
    deinit {
        print("deinit remote(\(self.id))")
        
        deinitClient()
    }
    
    static func from(peer: Peer, auth: Auth, eventLoopGroup: EventLoopGroup) async -> Remote {
        return .init(id: peer.name, peer: peer, auth: auth, eventLoopGroup: eventLoopGroup)
    }

    @MainActor
    func mdnsDiscovered(peer: Peer) {
        statemachine.tryEvent(.peerCameOnline)
    }
    
    @MainActor
    func mdnsOffline() {
        statemachine.tryEvent(.peerWentOffline)
    }
    
    func createConnection() async throws {
        
        let certificate = try await requestCertificate(peer: peer)
                
        guard let client = await initClient(peer: peer, certificate: certificate) else {
            throw RemoteError.failedToMakeWarpClient
        }
        
        self.connection = RemoteConnection(client: client)
    }
    
    private func requestCertificate(peer: Peer) async throws -> Bytes {
        
        guard let (host, _) = try? await peer.resolve() else {
            throw RemoteError.failedToResolvePeer
        }
        
        let regRequest = RegRequest.with {$0.hostname = ProcessInfo().hostName}
        
        guard case let .authPort(authPort) = peer.fetchCertInfo else {
            throw RemoteError.peerMissingFetchCertInfo
        }
        
        guard let response = try? await fetchCertV2(host: host, auth_port: authPort, regRequest: regRequest, eventLoopGroup: eventLoopGroup) else {
            throw RemoteError.failedToFetchLockedCertificate
        }
        
        
        guard let certBytes = try? auth.processRemoteCertificate(lockedCertificate: response.lockedCert) else {
            throw RemoteError.failedToUnlockCertificate
        }

        return certBytes
    }
    
    private func initClient(
        peer: Peer,
        certificate: Bytes
    ) async -> WarpAsyncClient? {
        guard let (host, port) = try? await peer.resolve() else {
            print("failed to resolvednsname")
            
            await mdnsOffline()
            
            return nil
        }
        
        print("\n\n resolved client: \(host):\(port)")
        
        let client = try? makeWarpClient(host: host,
                                         port: port,
                                         pinnedCertificate: certificate,
                                         hostnameOverride: peer.hostName,
                                         group: eventLoopGroup,
                                         connectivityStateDelegate: statemachine)
        
        print("initClient: \(String(describing: client))")
        
        guard let client = client else {
            print("failed to make warpclient")
            return nil
        }
        
        return client
    }
    
    func waitForConnected() async {
        
        print("waitForConnected called on remote: \(String(describing: self.displayName))")
        
        // The @Published state publisher will also send an initial value update to a new sink
        let statePublisher = $state
        
        return await withCheckedContinuation { continuation in
            
            // Creates a publisher that waits until the state is .waitingForDuplex or
            // .online and then sends exactly one value.
            // When the publisher is finished (after sending the value), the continuation
            // is resumed
            statePublisher.filter({$0 == .waitingForDuplex || $0 == .online})
                .first()
                .subscribe(Subscribers.Sink {receiveCompletion in
                    
                    print("waitForConnected resumed continuation for remote: \(String(describing: self.displayName))")
                    
                    continuation.resume()
                } receiveValue: { _ in
                    // pass
                })
        }
    }
    
    func waitingForDuplex() async throws {
        
        guard let client = client else {
            throw RemoteError.clientNotInitialized
        }
        
        print("NSLOG: starting waitingForDuplex rpccall")
        
        let response = try await client.waitingForDuplex(auth.lookupName)
        
        print("NSLOG: ended waitingForDuplex rpc call \(String(describing: response))")
    }
    
    
    func getRemoteMachineInfo() async throws {
        guard let client = client else {
            throw RemoteError.clientNotInitialized
        }
        
        let response = try? await client.getRemoteMachineInfo(auth.lookupName)
        
        DispatchQueue.main.async {
            self.displayName = response?.displayName
            self.userName = response?.userName
        }
    }
    
    func ping() async -> Bool {
        
        guard let client = client else {
            return false
        }
        
        print("NSLOG: starting ping rpccall")
        
        let response = try? await client.ping(auth.lookupName)
        
        print("NSLOG: ended ping rpc call \(String(describing: response))")
        
        if response != nil {
            print("succeed ping to \(self.id)")
        }
        
        if response == nil {
            return false
        } else {
            return true
        }
    }
    
    /// MARK: Transfers
    
    func requestTransfer(url: URL) async {
        
        guard let client = client else {
            return
        }
        
        var transferOperation = TransferToRemote.fromUrls(urls: [url], remote: self)
        
        self.transfersToRemote[transferOperation.timestamp] = transferOperation
        
        let opInfo = OpInfo.with({
            $0.ident = auth.identity
            $0.timestamp = transferOperation.timestamp
            $0.readableName = auth.networkConfig.hostname
            
        })
        
        let request = TransferOpRequest.with({
            $0.info = opInfo
            $0.senderName = auth.networkConfig.hostname
            $0.receiver = self.id
            $0.size = transferOperation.size
            $0.count = transferOperation.count
            $0.nameIfSingle = transferOperation.title
            $0.mimeIfSingle = transferOperation.mimeType
            $0.topDirBasenames = transferOperation.topDirBasenames
        })
        
        print("requestTransfer: created:\n \(request)")
        
        let result = try? await client.processTransferOpRequest(request)
        
        print("client.processTransferOpRequest(request) result: \(String(describing: result))")
        
        if result != nil {
            transferOperation.state = .requested
        } else {
            transferOperation.state = .failed(reason: "Failed to request")
        }
    }
        
    func startTransfer(transferOp: TransferFromRemote) async throws {
        
        guard transferOp.state == .requested else {
            throw TransferOpError.invalidStateToStartTransfer
        }
        
        guard let client = client else {
            throw RemoteError.clientNotInitialized
        }
        
        print("startTransfer: \(transferOp)")
        
        transferOp.state = .started
        
        let opInfo = OpInfo.with({
            $0.timestamp = transferOp.timestamp
            $0.ident = auth.identity
            $0.readableName = auth.networkConfig.hostname
        })
                
        let downloader = try TransferDownloader(topDirBasenames: transferOp.topDirBasenames, progress: transferOp.progress)
        
        transferOp.localSaveUrls = downloader.savePaths
        
        let response = client.startTransfer(opInfo)
        
        for try await chunk in response {
            
            // Increment the progress metric
            Task {
                await transferOp.progress.increment(by: chunk.chunk.count)
            }

            do {
                try downloader.handleChunk(chunk: chunk)
            } catch {
                
                try? await stopTransfer(timestamp: transferOp.timestamp, error: true)
                
                print(error)
                transferOp.state = .failed(reason: "\(error)")
                
                throw error
            }
        }
        
        transferOp.state = .completed
        
        print("done transfering")
    }
    
    func cancelTransferOpRequest(timestamp: UInt64) async throws {
        try await client?.cancelTransferOpRequest(opInfo(for: timestamp))
    }
    
    func stopTransfer(timestamp: UInt64, error: Bool=false) async throws {
        let stopInfo: StopInfo = .with {
            $0.info = opInfo(for: timestamp)
            $0.error = error
        }
        
        try await client?.stopTransfer(stopInfo)
    }
    
    func opInfo(for timestamp: UInt64) -> OpInfo {
        return OpInfo.with({
            $0.timestamp = timestamp
            $0.ident = auth.identity
            $0.readableName = auth.networkConfig.hostname
        })
    }
}



extension Auth {
    var lookupName: LookupName {
        LookupName.with {
            $0.id = self.identity
            $0.readableName = self.networkConfig.hostname
        }
    }
}

/// MARK: Create connection for remote

class RemoteConnection {
    let client: WarpAsyncClient
    
    init(client: WarpAsyncClient) {
        self.client = client
    }
    
    deinit {
        try? client.channel.close().wait()
    }
}
