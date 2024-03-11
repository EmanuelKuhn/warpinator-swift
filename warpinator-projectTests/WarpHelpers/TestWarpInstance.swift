//
//  TestWarpInstance.swift
//  warpinator-projectTests
//
//  Created by Emanuel on 23/04/2022.
//

import Foundation

@testable import warpinator_project

import GRPC
import NIO

class TestWarpInstance {
    
    let networkConfig: NetworkConfig
    let auth: Auth
    
    let warpServer: WarpServer
    let discovery: TestDiscovery
    
    let certServer: CertServerV2
    
    let remoteRegistration: RemoteRegistration
    
    let eventLoopGroup: EventLoopGroup
    
    init(identity: String, port: Int, authPort: Int) {
        
        self.eventLoopGroup = PlatformSupport.makeEventLoopGroup(loopCount: 2)
        
        self.networkConfig = .init()
        
        self.auth = Auth(networkConfig: self.networkConfig, identity: "\(identity)-\(port)")
        
        self.discovery = TestDiscovery()
        
        self.remoteRegistration = RemoteRegistration(discovery: self.discovery, auth: auth, clientEventLoopGroup: eventLoopGroup)
        
        self.certServer = CertServerV2(auth: auth, auth_port: authPort)
        
        self.warpServer = WarpServer(auth: auth, remoteRegistration: remoteRegistration, port: port)
    }
    
    func run(callback: @escaping (Result<Void, Error>)->(), flag: Bool=false) async {
        
        Task {
            try self.certServer.run(eventLoopGroup: eventLoopGroup) {
                Task {
                    try self.warpServer.run(eventLoopGroup: self.eventLoopGroup) {result in
                        callback(result)
                        print(flag)
                    }
                }
            }
        }
    }
    
    var certificate: [UInt8] {
        Auth.pemEncoded(certificate: auth.serverIdentity.certificate).bytes
    }
    
    var lookupName: LookupName {
        var result = LookupName()
        result.id = self.auth.identity
        result.readableName = "\(warpServer.port),\(certServer.auth_port)"
        
        return result
    }
    
    func getPeer() -> TestPeer {
        return TestPeer(name: self.auth.identity, hostName: self.networkConfig.hostname, authPort: self.certServer.auth_port, resolveResult: ("127.0.0.1", warpServer.port))
        
    }
    
    func addPeer(_ peer: TestPeer) {
        discovery.callListeners(change: .added(peer: peer))
    }
    
    /// Make a client connection to this Warp instance.
    func connect() async throws -> WarpAsyncClient {
        let peer = getPeer()
        let (host, port) = try await peer.resolve()

        
        return try makeWarpClient(host: host,
                                  port: port,
                                  pinnedCertificate: certificate,
                                  hostnameOverride: peer.hostName,
                                  group: PlatformSupport.makeEventLoopGroup(loopCount: 1))
    }
    
    func close() throws {
        try warpServer.close()
        try certServer.close()
        
        try self.eventLoopGroup.syncShutdownGracefully()
    }
}
