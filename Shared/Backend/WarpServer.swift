//
//  WarpServer.swift
//  warpinator-project
//
//  Created by Emanuel on 19/03/2022.
//

import Foundation

import System

import GRPC
import NIOCore
import NIOPosix

import NIOSSL

class WarpServer {
        
    
    let auth: Auth
    
    let address: String
    let port: Int
    
    // The provider that implements the WarpAsyncProvider protocol
    let provider: WarpAsyncProvider
    
    init(auth: Auth, remoteRegistration: RemoteRegistration) {
        self.auth = auth
        self.provider = WarpServerProvider(remoteRegistration: remoteRegistration)
        
        self.address = "::"
        self.port = 42000
    }
    
    
    func run() throws {
        
        print("run()")
        
        // Create an event loop group for the server to run on.
        let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        defer {
        try! group.syncShutdownGracefully()
        }

        let certificateDer = auth.serverIdentity.certificate.derEncoded.bytes
        let certificate = try NIOSSLCertificate(bytes: certificateDer, format: .der)
        
        let privateKeyDer = try auth.serverIdentity.keyPair.encodedPrivateKey().bytes
        let privateKey = try NIOSSLPrivateKey(bytes: privateKeyDer, format: .der)
        
        let grpcTLSConfig = GRPCTLSConfiguration.makeServerConfigurationBackedByNIOSSL(certificateChain: [.certificate(certificate)], privateKey: .privateKey(privateKey))
        
        // Start the server and print its address once it has started.
        let server = Server.usingTLS(with: grpcTLSConfig, on: group)
            .withServiceProviders([provider])
            .bind(host: self.address, port: self.port)
        
        server.map {
            $0.channel.localAddress
        }.whenSuccess { address in
            print("server started on port \(address!.port!)")
        }
                
        server.map {
            $0.channel.localAddress
        }.whenFailure({ error in
            print("server failed to start \(error)")
        })
        
        

        // Wait on the server's `onClose` future to stop the program from exiting.
        _ = try server.flatMap {
            $0.onClose
        }.wait()
    }
    
}
