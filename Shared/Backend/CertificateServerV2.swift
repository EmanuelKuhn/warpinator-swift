//
//  CertificateServerV2.swift
//  warpinator-project
//
//  Created by Emanuel on 09/02/2022.
//

import Foundation

import System

import GRPC
import NIOCore
import NIOPosix


class CertServerV2 {
    
    let auth: Auth
    let address: String
    let auth_port: Int
    
    private var server: EventLoopFuture<Server>! = nil
    
    init(auth: Auth, auth_port: Int) {
        self.auth = auth
        self.address = "::"
        self.auth_port = auth_port
    }
    
    var stateCallbacks: [(SocketAddress?) -> Void] = []
    
    func run(eventLoopGroup: EventLoopGroup, callback: (()->Void)?=nil) throws {
        
        print("run()")
        
//        // Create an event loop group for the server to run on.
//        let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
//        defer {
//        try! group.syncShutdownGracefully()
//        }

        let provider = WarpRegistrationServicer(auth: self.auth)

        // Start the server and print its address once it has started.
        let server = Server.insecure(group: eventLoopGroup)
            .withServiceProviders([provider])
            .bind(host: self.address, port: self.auth_port)

        server.map {
            $0.channel.localAddress
        }.whenSuccess { address in
            print("server started on port \(address!.port!)")

            if let callback = callback {
                callback()
            }
            
            print("certserver started called callbacks")
        }
        
        server.map {
            $0.channel.localAddress
        }.whenFailure({ error in
            print("cert server failed to start \(error)")
        })
        

        // Wait on the server's `onClose` future to stop the program from exiting.
        _ = try server.flatMap {
            $0.onClose
        }.wait()
    }
    
    func close() throws {
        try server?.map({
            $0.channel.close()
            $0.initiateGracefulShutdown()
            $0.close()
        }).wait()
    }

}
