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


class Remote {
            
    let name: String
        
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
    
    init(name: String, mdnsPeer: MDNSPeer, auth: Auth) async {
        self.name = name
        self.mdnsPeer = mdnsPeer
        
        self.auth = auth
        
        Task {
            await self.setup()
        }
    }
    
    enum InitClientError: Error {
        case failedToResolveMDNS
        case failedToMakeWarpClient
    }
    
    func initClient() async throws {
        guard let (host, port) = try? await self.mdnsPeer.resolveDNSName() else {
            print("failed to resolvednsname")
            throw InitClientError.failedToResolveMDNS
        }
                
        self._client = try? makeWarpClient(host: host, port: port, pinnedCertificate: self.certificate!, hostnameOverride: self.mdnsPeer.hostName)
        
        print("initClient: \(String(describing: _client))")
        
        if self._client == nil {
            throw InitClientError.failedToMakeWarpClient
        }
    }
    
    deinit {
        print("deinit remote(\(self.name))")
        
        Task {
            try? await self.client.channel.close().wait()
        }
    }
    
    func setup() async {
        let certSuccess = await requestCertificate()
        
        print("remote \(self.name): successfully fetched cert: \(certSuccess)")
        
        if !certSuccess {
            return
        }
                
    }
    
    static func from(mdnsPeer: MDNSPeer, auth: Auth) async -> Remote {
        return await .init(name: mdnsPeer.name, mdnsPeer: mdnsPeer, auth: auth)
    }
    
    func setActive(_ active: Bool) {
        self.isActive = active
    }
    
    func update(with mdnsPeer: MDNSPeer) {
        assert(mdnsPeer.name == self.name)
        
        
        print("TODO: update with peer")
    }
    
    func requestCertificate() async -> Bool {
        
        print("\(self.name): requestCertificate: start")
    
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

    
    func ping() async throws -> Bool {        
        NSLog("starting ping rpccall")
        
        let response = try? await client.ping(self.lookupName)


        NSLog("ended ping rpc call \(String(describing: response))")

        if response != nil {
            print("succeed ping to \(self.name)")
        }
        
        if response == nil {
            return false
        } else {
            return true
        }
    }
    
    
}
