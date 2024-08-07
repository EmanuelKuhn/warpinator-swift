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
    
    case failedToGetDuplex
    
    case failedToPing
}

struct ResolvedHost {
    let host: String
    let port: Int
}

protocol RemoteProtocol {
    
    var peer: Peer { get }
    var transfers: CurrentValueSubject<Array<TransferOp>, Never> { get }
    var state: RemoteState { get }
    
    func ping() async throws
    
    func requestTransfer(urls: [URL]) async throws
    
    func statePublisher() -> AnyPublisher<RemoteState, Never>
    
}

protocol TransferCapabilities: AnyObject {
    var transfersToRemote: Dictionary<UInt64, TransferToRemote>  { get set }
    var transfersFromRemote: Dictionary<UInt64, TransferFromRemote> { get set }

    func cancelTransferOpRequest(timestamp: UInt64) async throws
    func stopTransfer(timestamp: UInt64, error: Bool) async throws
    func startTransfer(transferOp: TransferFromRemote, downloader: TransferDownloader) async throws
}

// For allowing Remote to be Mocked, extract into a seperate protocol
typealias FullRemoteProtocol = RemoteProtocol & TransferCapabilities

class Remote: FullRemoteProtocol, ObservableObject {
    
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
    
    func statePublisher() -> AnyPublisher<RemoteState, Never> {
        return $state.eraseToAnyPublisher()
    }
    
    var peer: Peer
    
    @Published
    var resolved: ResolvedHost? = nil

    let id: String
    
    private let auth: Auth
    
    private var certificate: Bytes? = nil
    private var connection: RemoteConnection?
    
    @Published
    var remoteMachineInfo: RemoteMachineInfo? = nil
    
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
    
    // Handle statemachine state changes
    func enterState(_ state: RemoteState) async {
        switch state {
        case .fetchingCertificate, .retrying:
            await statemachine.tryEvent(await establishDuplexConnection())
        case .offline:
            break
//            deinitClient()
        case .waitingForDuplex:
            break
        case .online:
            try? await getRemoteMachineInfo()
        case .failure(_):
            break
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
        // Peer came online and might have changed port.
        self.peer = peer
        
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
                                         hostnameOverride: host,
                                         group: eventLoopGroup,
                                         connectivityStateDelegate: statemachine)
        
        print("initClient: \(String(describing: client))")
        
        self.resolved = .init(host: host, port: port)
        
        guard let client = client else {
            print("failed to make warpclient")
            return nil
        }
        
        return client
    }
    
    func waitForConnected() async {
        
        print("waitForConnected called on remote: \(String(describing: self.peer.hostName))")
                
        // Hint to retry if failed
        await self.statemachine.tryEvent(.retryTimerFired)
        
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
                    
                    print("waitForConnected resumed continuation for remote: \(String(describing: self.peer.hostName))")
                    
                    continuation.resume()
                } receiveValue: { _ in
                    // pass
                })
        }
    }
    
    func establishDuplexConnection() async -> RemoteEvent {
        do {
            try await createConnection()

            try await ping()
            
            // After succesfull ping wait for duplex connection
            return await waitForDuplex()
            
        } catch RemoteError.failedToResolvePeer {
            return .peerWentOffline
        } catch let error as RemoteError {
            return .peerFailure(error)
        } catch {
            return .peerFailure(.failedToMakeWarpClient)
        }
    }
    
    func waitForDuplex() async -> RemoteEvent {
        
        guard let client = client else {
            return .peerFailure(.clientNotInitialized)
        }
        
        do {
            // Don't care about response value
            let _ = try await client.waitingForDuplex(auth.lookupName)
            
            return .gotDuplex
        } catch {
            return .peerFailure(.failedToGetDuplex)
        }
    }
    
    
    func getRemoteMachineInfo() async throws {
        guard let client = client else {
            throw RemoteError.clientNotInitialized
        }
        
        let response = try? await client.getRemoteMachineInfo(auth.lookupName)
        
        self.remoteMachineInfo = response
    }
    
    func ping() async throws {
        
        guard let client = client else {
            throw RemoteError.clientNotInitialized
        }
                
        let response = try? await client.ping(auth.lookupName)
        
        print("NSLOG: ended ping rpc call \(String(describing: response))")
        
        if response == nil {
            throw RemoteError.failedToPing
        }
    }
    
    /// MARK: Transfers
    
    func requestTransfer(urls: [URL]) async {
        
        guard let client = client else {
            return
        }
        
        var transferOperation = TransferToRemote.fromUrls(urls: urls, remote: self)
        
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
            transferOperation.tryEvent(event: .requested)
        } else {
            transferOperation.tryEvent(event: .failure(reason: "Failed to request"))
        }
    }
        
    func startTransfer(transferOp: TransferFromRemote, downloader: TransferDownloader) async throws {
        
        guard transferOp.state == .requested else {
            throw TransferOpError.invalidStateToStartTransfer
        }
        
        guard let client = client else {
            throw RemoteError.clientNotInitialized
        }
        
        print("startTransfer: \(transferOp)")
        
        transferOp.tryEvent(event: .start)
        
        let opInfo = OpInfo.with({
            $0.timestamp = transferOp.timestamp
            $0.ident = auth.identity
            $0.readableName = auth.networkConfig.hostname
        })
        
        transferOp.localSaveUrls = downloader.saveURLs
        
        let response = client.startTransfer(opInfo)
        
        do {
            try await receiveChunks(transferOp: transferOp, downloader: downloader, response: response)
            
            transferOp.tryEvent(event: .completed)
        } catch {
            transferOp.tryEvent(event: .failure(reason: error.localizedDescription))
        }
    }
    
    private func receiveChunks(transferOp: TransferOp, downloader: TransferDownloader, response: GRPCAsyncResponseStream<FileChunk>) async throws {
        for try await chunk in response {
            guard transferOp.state == .started else {
                throw TransferOpError.invalidStateWhileDownloading
            }
            
            // Increment the progress metric
            Task {
                await transferOp.progress.increment(by: chunk.chunk.count)
            }

            try downloader.handleChunk(chunk: chunk)
        }
        
        try downloader.finish()
    }
    
    func cancelTransferOpRequest(timestamp: UInt64) async throws {
        try await client?.cancelTransferOpRequest(opInfo(for: timestamp))
    }
    
    func stopTransfer(timestamp: UInt64, error: Bool) async throws {
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
