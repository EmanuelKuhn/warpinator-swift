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

enum RemoteError: Error {
    case peerNotInitialised
    
    case clientNotInitialized
    
    case failedToFetchCertificate
    case failedToMakeWarpClient
}

class Remote {
    
    private var connectionLifeCycle: RemoteConnectionLifeCycle!
    
    var peer: Peer
    
    var statePublisher: AnyPublisher<RemoteState, Never> {
        get async {
            return await connectionLifeCycle.statePublisher
        }
    }
    
    var state: RemoteState {
        get async {
            return await connectionLifeCycle.state
        }
    }
    
    let id: String
    
    private let auth: Auth
    
    private var certificate: Bytes? = nil
    private var connection: RemoteConnection?
    
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
            
            transfers.value = merged
        }
    }
    
    var transfersFromRemote: Dictionary<UInt64, TransferFromRemote> = .init() {
        willSet {
            
            var merged: [TransferOp] = Array(newValue.values)
            merged.append(contentsOf: Array(transfersToRemote.values))
            
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
    
    init(id: String, peer: Peer, auth: Auth, eventLoopGroup: EventLoopGroup) async {
        self.id = id
        self.auth = auth
        
        self.eventLoopGroup = eventLoopGroup
        
        self.peer = peer
        
        self.connectionLifeCycle = .init(remote: self)
        
        self.mdnsDiscovered(peer: peer)
    }
    
    deinit {
        print("deinit remote(\(self.id))")
        
        deinitClient()
    }
    
    static func from(peer: Peer, auth: Auth, eventLoopGroup: EventLoopGroup) async -> Remote {
        return await .init(id: peer.name, peer: peer, auth: auth, eventLoopGroup: eventLoopGroup)
    }
    
    func mdnsDiscovered(peer: Peer) {
        Task {
            await connectionLifeCycle.mdnsDiscovered(peer: peer)
        }
    }
    
    func mdnsOffline() {
        Task {
            await connectionLifeCycle.mdnsOffline()
        }
    }
    
    func createConnection() async throws {
        
        guard let certificate = await requestCertificate(peer: peer) else {
            throw RemoteError.failedToFetchCertificate
        }
        
        guard let client = await initClient(peer: peer, certificate: certificate) else {
            throw RemoteError.failedToMakeWarpClient
        }
        
        self.connection = RemoteConnection(client: client)
    }
    
    private func requestCertificate(peer: Peer) async -> Bytes? {
        
        guard let (host, _) = try? await peer.resolve() else {
            print("failed to resolve")
            
            await connectionLifeCycle.mdnsOffline()
            
            return nil
        }
        
        let regRequest = RegRequest.with {$0.hostname = ProcessInfo().hostName}
        
        guard case let .authPort(authPort) = peer.fetchCertInfo else {
            return nil
        }
        
        guard let response = try? await fetchCertV2(host: host, auth_port: authPort, regRequest: regRequest, eventLoopGroup: eventLoopGroup) else {
            print("requestCertificate: failed fetchCertV2")
            
            return nil
        }
        
        guard let certBytes = try? auth.processRemoteCertificate(lockedCertificate: response.lockedCert) else {
            print("failed processing remote certificate")
            
            return nil
        }
        
        return certBytes
    }
    
    private func initClient(
        peer: Peer,
        certificate: Bytes
    ) async -> WarpAsyncClient? {
        guard let (host, port) = try? await peer.resolve() else {
            print("failed to resolvednsname")
            
            await connectionLifeCycle.mdnsOffline()
            
            return nil
        }
        
        let client = try? makeWarpClient(host: host,
                                         port: port,
                                         pinnedCertificate: certificate,
                                         hostnameOverride: peer.hostName,
                                         group: eventLoopGroup,
                                         connectivityStateDelegate: connectionLifeCycle)
        
        print("initClient: \(String(describing: client))")
        
        guard let client = client else {
            print("failed to make warpclient")
            return nil
        }
        
        return client
    }
    
    func waitForConnected() async {
        
        let statePublisher = await statePublisher
        
        return await withCheckedContinuation { continuation in
            
            // Creates a publisher that waits until the state is .waitingForDuplex or
            // .online and then sends exactly one value.
            // When the publisher is finished (after sending the value), the continuation
            // is resumed
            statePublisher.filter({$0 == .waitingForDuplex || $0 == .online})
                .first()
                .subscribe(Subscribers.Sink {receiveCompletion in
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
        
        NSLog("starting waitingForDuplex rpccall")
        
        let response = try await client.waitingForDuplex(auth.lookupName)
        
        NSLog("ended waitingForDuplex rpc call \(String(describing: response))")
    }
    
    func ping() async -> Bool {
        
        guard let client = client else {
            return false
        }
        
        NSLog("starting ping rpccall")
        
        let response = try? await client.ping(auth.lookupName)
        
        NSLog("ended ping rpc call \(String(describing: response))")
        
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
            transferOperation.state = .failed
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
        
        let response = client.startTransfer(opInfo)
        
        for try await chunk in response {
            print("new chunk")
            
            do {
                
                var newChunk = chunk
                
                newChunk.chunk = Data()
                
                print(newChunk)
                
                let fileUrl = URL.init(fileURLWithPath: chunk.relativePath, relativeTo: try getDocumentsDirectory())
                
                if chunk.hasTime {
                    let time = chunk.time
                    
                    try chunk.chunk.write(to: fileUrl, options: .atomic)
                    
                    // Timestamp is mtime seconds + mtimeUsec microseconds
                    let timestamp: NSDate = NSDate(timeIntervalSince1970: .init(time.mtime))
                        .addingTimeInterval(.init(time.mtimeUsec) * 10e-6)
                    
                    try! FileManager.default.setAttributes([.modificationDate: timestamp], ofItemAtPath: fileUrl.path)
                } else {
                    try chunk.chunk.append(fileURL: fileUrl)
                }
            } catch {
                print(error)
                transferOp.state = .failed
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
