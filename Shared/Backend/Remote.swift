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

enum RemoteState {
    case initial
    case waitingForDuplex
    case online
    case unreachable
    case transientFailure
}

class RemoteStateManager: ConnectivityStateDelegate {
        
    var stateSubject = CurrentValueSubject<RemoteState, Never>(.initial)
    
    var state: RemoteState {
        get {
            stateSubject.value
        }
        
        set(newState) {
            stateSubject.value = newState
        }
    }
        
    func connectivityStateDidChange(from oldState: ConnectivityState, to newState: ConnectivityState) {
        
        // If we're not online, and just connected to remote, set status to waiting for duplex
        if state != .online && newState == .ready {
            state = .waitingForDuplex
        }
        
        if newState == .shutdown {
            state = .unreachable
        }
        
        if newState == .transientFailure {
            state = .transientFailure
        }
    }
    
    func waitForConnected() async {
        return await withCheckedContinuation { continuation in
            
            // Creates a publisher that waits until the state is .waitingForDuplex or
            // .online and then sends exactly one value.
            // When the publisher is finished (after sending the value), the continuation
            // is resumed
            stateSubject.filter({$0 == .waitingForDuplex || $0 == .online})
                .first()
                .subscribe(Subscribers.Sink {receiveCompletion in
                    continuation.resume()
                } receiveValue: { _ in
                    // pass
                })
        }
    }
}

class Remote {
    
    let remoteState = RemoteStateManager()
    
    let id: String
    
    let peer: Peer
    
    var isActive = true
    
    var certificate: Bytes? = nil
    
    private let auth: Auth
    
    private var _client: WarpAsyncClient?
    
    
    // The client property should ideally always return a working client
    // throws when it failed to initialize a client
    private var client: WarpAsyncClient {
        get async throws {
            if _client != nil {
                return _client!
            }
            
            try! await self.initClient()
            
            return _client!
        }
    }
    
    var transfersToRemote: Dictionary<UInt64, TransferToRemote> = .init()
    var transfersFromRemote: Dictionary<UInt64, TransferFromRemote> = .init()
    
    let eventLoopGroup: EventLoopGroup
    
    init(id: String, peer: Peer, auth: Auth, eventLoopGroup: EventLoopGroup) async {
        self.id = id
        self.peer = peer
        
        self.auth = auth
        
        self.eventLoopGroup = eventLoopGroup
        
        Task {
            do {
                try await self.setup()
            } catch {
                remoteState.state = .unreachable
                
                print("Could not setup remote: \(self.peer.name)")
            }
        }
    }
    
    enum InitClientError: Error {
        case failedToResolveMDNS
        case failedToMakeWarpClient
        case failedWaitingForDuplex
    }
    
    func initClient() async throws {
        guard let (host, port) = try? await self.peer.resolve() else {
            print("failed to resolvednsname")
            throw InitClientError.failedToResolveMDNS
        }
        
        self._client = try? makeWarpClient(host: host,
                                           port: port,
                                           pinnedCertificate: self.certificate!,
                                           hostnameOverride: self.peer.hostName,
                                           group: self.eventLoopGroup,
                                           connectivityStateDelegate: self.remoteState)
        
        print("initClient: \(String(describing: _client))")
        
        if self._client == nil {
            throw InitClientError.failedToMakeWarpClient
        }
    }
    
    deinit {
        print("deinit remote(\(self.id))")
        
        Task {
            try? await self.client.channel.close().wait()
        }
    }
    
    func setup() async throws {
        let certSuccess = await requestCertificate()
        
        print("remote \(self.id): successfully fetched cert: \(certSuccess)")
        
        if !certSuccess {
            return
        }
        
        try await waitingForDuplex()
        
        let remoteInfo = try? await client.getRemoteMachineInfo(lookupName)
        
        print("remoteInfo: \(String(describing: remoteInfo))")
        
    }
    
    static func from(peer: Peer, auth: Auth, eventLoopGroup: EventLoopGroup) async -> Remote {
        return await .init(id: peer.name, peer: peer, auth: auth, eventLoopGroup: eventLoopGroup)
    }
    
    func setActive(_ active: Bool) {
        self.isActive = active
    }
    
    func update(with peer: Peer) {
        assert(peer.name == self.id)
        
        
        print("TODO: update with peer")
    }
    
    func requestCertificate() async -> Bool {
        
        print("\(self.id): requestCertificate: start")
        
        guard let (host, _) = try? await self.peer.resolve() else {
            print("failed to resolve")
            return false
        }
        
        let regRequest = RegRequest.with {$0.hostname = ProcessInfo().hostName}
        
        guard case let .authPort(authPort) = self.peer.fetchCertInfo else {
            return false
        }
        
        guard let response = try? await fetchCertV2(host: host, auth_port: authPort, regRequest: regRequest, eventLoopGroup: eventLoopGroup) else {
            print("requestCertificate: failed fetchCertV2")
            
            return false
        }
        
        guard let certBytes = try? self.auth.processRemoteCertificate(lockedCertificate: response.lockedCert) else {
            print("failed processing remote certificate")
            
            return false
        }
        
        self.certificate = certBytes
        
        print("requestCertificate: successfully set certificate: \(String(describing: self.certificate?.count))")
        
        
        return true
    }
    
    var lookupName: LookupName {
        LookupName.with {
            $0.id = auth.identity
            $0.readableName = auth.networkConfig.hostname
        }
    }

    
    func waitingForDuplex() async throws {
        NSLog("starting waitingForDuplex rpccall")

        let response = try await client.waitingForDuplex(lookupName)
        
        NSLog("ended waitingForDuplex rpc call \(String(describing: response))")
        
        remoteState.state = .online
    }
    
    func ping() async throws -> Bool {
        NSLog("starting ping rpccall")
        
        let response = try? await client.ping(self.lookupName)
        
        
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
    
    func requestTransfer(url: URL) async throws {
                
        var transferOperation = try TransferToRemote.fromUrls(urls: [url])
        
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
            $0.size = UInt64(url.fileSize() ?? 10000)
            $0.count = UInt64(1)
            $0.nameIfSingle = url.lastPathComponent
            $0.mimeIfSingle = url.mime()?.identifier ?? "application/octet-stream"
            $0.topDirBasenames = [url.lastPathComponent]
        })
        
        print("requestTransfer: created:\n \(request)")
        
        let result = try? await client.processTransferOpRequest(request)
        
        print("client.processTransferOpRequest(request) result: \(result)")
        
        if result != nil {
            transferOperation.state = .requested
        } else {
            transferOperation.state = .failed
        }
    }
    
    func startTransfer(timestamp: UInt64) async throws {
        
        print("startTransfer")

        let transferOp = transfersFromRemote[timestamp]!

        print("startTransfer: \(transferOp)")

        
        let opInfo = OpInfo.with({
            $0.timestamp = transferOp.timestamp
            $0.ident = auth.identity
            $0.readableName = auth.networkConfig.hostname
        })
        
        let response = try! await client.startTransfer(opInfo)
        
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
            }
        }
        
        print("done transfering")
    }
}

