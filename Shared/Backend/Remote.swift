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
    
    let mdnsPeer: MDNSPeer
    
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
    
    init(id: String, mdnsPeer: MDNSPeer, auth: Auth) async {
        self.id = id
        self.mdnsPeer = mdnsPeer
        
        self.auth = auth
        
        Task {
            do {
                try await self.setup()
            } catch {
                remoteState.state = .unreachable
                
                print("Could not setup remote: \(self.mdnsPeer.name)")
            }
        }
    }
    
    enum InitClientError: Error {
        case failedToResolveMDNS
        case failedToMakeWarpClient
        case failedWaitingForDuplex
    }
    
    func initClient() async throws {
        guard let (host, port) = try? await self.mdnsPeer.resolveDNSName() else {
            print("failed to resolvednsname")
            throw InitClientError.failedToResolveMDNS
        }
        
        self._client = try? makeWarpClient(host: host,
                                           port: port,
                                           pinnedCertificate: self.certificate!,
                                           hostnameOverride: self.mdnsPeer.hostName,
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
    
    static func from(mdnsPeer: MDNSPeer, auth: Auth) async -> Remote {
        return await .init(id: mdnsPeer.name, mdnsPeer: mdnsPeer, auth: auth)
    }
    
    func setActive(_ active: Bool) {
        self.isActive = active
    }
    
    func update(with mdnsPeer: MDNSPeer) {
        assert(mdnsPeer.name == self.id)
        
        
        print("TODO: update with peer")
    }
    
    func requestCertificate() async -> Bool {
        
        print("\(self.id): requestCertificate: start")
        
        guard let (host, _) = try? await self.mdnsPeer.resolveDNSName() else {
            print("failed to resolve")
            return false
        }
        
        let regRequest = RegRequest.with {$0.hostname = ProcessInfo().hostName}
        
        guard let response = try? await fetchCertV2(host: host, auth_port: self.mdnsPeer.authPort ?? 42001, regRequest: regRequest) else {
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
    
    
}
