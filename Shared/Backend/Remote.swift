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

//actor RemoteActor {
//
//    enum RemoteActorError: Error {
//        case remoteCertificateIsNil
//    }
//
//    let auth: Auth
//
//    private var _warpClient: WarpGRPCClient? = nil
//
////    private getWarpClient()
//
//    init(auth: Auth) {
//        self.auth = auth
//    }
//
////    func initWarpClient(remote: Remote) async throws {
////        self.warpClient =
////    }
//
//    var lookupName: LookupName {
//        LookupName.with {
//            $0.id = auth.identity
//            $0.readableName = auth.hostName
//        }
//    }
//
////    /// Function abstracting the steps of resolving the remote and creating the rpc call
////    func rpcCall<I, O>(remote: Remote, rpcCall: WarpRPCCallFunc<I, O>) async throws -> O? {
////
////        guard let remoteCertificate = remote.certificate else {
////            throw RemoteActorError.remoteCertificateIsNil
////        }
////
////        guard let (host, port) = try? await remote.mdnsPeer.resolveDNSName() else {
////            print("rpcCall: failed to resolve")
////            return nil
////        }
////
////        NSLog("rpc call resolved host and port")
////
////        return try warpRPCCall(host: host, port: port, pinnedCertificate: remoteCertificate, hostnameOverride: remote.mdnsPeer.txtRecord["hostname"]!, rpcCall: rpcCall)
////    }
//
////    func ping(remote: Remote) async throws -> Bool {
////        NSLog("starting ping rpccall")
////        let response = try await rpcCall(remote: remote) { client -> UnaryCall<LookupName, VoidType> in
////            NSLog("Just before client.ping")
////
////            let res = client.ping(self.lookupName)
////
////            NSLog("Just after client.ping")
////
////            return res
////        }
////
////        NSLog("ended ping rpc call")
////
////        if response == nil {
////            return false
////        } else {
////            return true
////        }
////    }
//
////    func getRemoteMachineInfo(remote: Remote) async throws {
////
////        let response = try await rpcCall(remote: remote) { client in
////
////            return client.getRemoteMachineInfo(self.lookupName)
////        }
////
////        guard let info = response else {
////            print("failed to fetch remote machine info")
////
////            return
////        }
////
////        print("fetched remote machine info: \(info)")
////    }
//
//    func requestCertificate(remote: Remote) async -> Bytes? {
//
//        guard let (host, _) = try? await remote.mdnsPeer.resolveDNSName() else {
//            print("failed to resolve")
//            return nil
//        }
//
//        let regRequest = RegRequest.with {$0.hostname = ProcessInfo().hostName}
//
//        guard let response = try? await fetchCertV2(host: host, auth_port: remote.mdnsPeer.authPort ?? 42001, regRequest: regRequest) else {
//            return nil
//
//        }
//
//        do {
//            return try self.auth.processRemoteCertificate(lockedCertificate: response.lockedCert)
//        } catch {
//            print(error)
//
//            return nil
//        }
//    }
//}


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
        
//        print("requestCertificate: resolved host: \(host)")

        let regRequest = RegRequest.with {$0.hostname = ProcessInfo().hostName}

//        let fetchTask = Task {
//            return try? fetchCertV2(host: host, auth_port: self.mdnsPeer.authPort ?? 42001, regRequest: regRequest)
//        }
        
        guard let response = try? await fetchCertV2(host: host, auth_port: self.mdnsPeer.authPort ?? 42001, regRequest: regRequest) else {
            print("requestCertificate: failed fetchCertV2")
            
            return false
        }
        
//        print("requestCertificate: succeeded fetchCertV2")

    
            
        guard let certBytes = try? self.auth.processRemoteCertificate(lockedCertificate: response.lockedCert) else {
            print("failed processing remote certificate")
            
            return false
        }
                
        self.certificate = certBytes
        
        print("requestCertificate: successfully set certificate: \(self.certificate?.count)")

        
        return true
    }
    
        var lookupName: LookupName {
            LookupName.with {
                $0.id = auth.identity
                $0.readableName = auth.hostName
            }
        }

    
    func ping() async throws -> Bool {
//        NSLog("init client before ping")
        
//        let clientSuc = await self.initClient()
        
//        print("ping(): clientSuc: \(clientSuc)")
        
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
