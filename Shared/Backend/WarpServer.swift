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
    let provider: WarpServerProvider
    
    private var server: EventLoopFuture<Server>! = nil
    
    init(auth: Auth, remoteRegistration: RemoteRegistration, port: Int) {
        self.auth = auth
        self.provider = WarpServerProvider(remoteRegistration: remoteRegistration)
        
        self.address = "::"
        self.port = port
    }
    
    var stateCallbacks: [(SocketAddress?) -> Void] = []
    
    func runAsync(eventLoopGroup: EventLoopGroup) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.run(eventLoopGroup: eventLoopGroup, completion: { result in
                continuation.resume(with: result)
            })
        }
    }
    
    private func run(eventLoopGroup: EventLoopGroup, completion: @escaping (Result<Void, Error>) -> Void) {
        
        assert(server == nil)
        
        print("run()")

        let certificateDer = auth.serverIdentity.certificate.derEncoded.bytes
        
        let certificate: NIOSSLCertificate
        let privateKeyDer: [UInt8]
        let privateKey: NIOSSLPrivateKey
        
        do {
            certificate = try NIOSSLCertificate(bytes: certificateDer, format: .der)
            
            privateKeyDer = try auth.serverIdentity.keyPair.encodedPrivateKey().bytes
            privateKey = try NIOSSLPrivateKey(bytes: privateKeyDer, format: .der)
        } catch {
            completion(.failure(error))
            
            return
        }
        
        let grpcTLSConfig = GRPCTLSConfiguration.makeServerConfigurationBackedByNIOSSL(certificateChain: [.certificate(certificate)], privateKey: .privateKey(privateKey))
        
        // Start the server and print its address once it has started.
        server = Server.usingTLS(with: grpcTLSConfig, on: eventLoopGroup)
            .withServiceProviders([provider])
            .bind(host: self.address, port: self.port)
        
        server.map {
            $0.channel.localAddress
        }.whenSuccess { address in
            print("server started on port \(address!.port!)")

            completion(.success(()))

            print("server started called callbacks")
        }
                
        server.map {
            $0.channel.localAddress
        }.whenFailure({ error in
            print("server failed to start \(error) (\(self.address):\(self.port)")
            
            completion(.failure(error))
        })
    }
    
    func close() throws {
        try server?.flatMap({
            $0.initiateGracefulShutdown()
        }).wait()
    }
    
    deinit {
        try? close()
    }
}
