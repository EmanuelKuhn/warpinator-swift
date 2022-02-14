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
    
    init(auth: Auth) {
        self.auth = auth
        self.address = "::"
        self.auth_port = 42001
    }
    
    
    func run() throws {
        
        print("run()")
        
        // Create an event loop group for the server to run on.
        let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        defer {
        try! group.syncShutdownGracefully()
        }

        let provider = WarpRegistrationServicer(auth: self.auth)

        // Start the server and print its address once it has started.
        let server = Server.insecure(group: group)
            .withServiceProviders([provider])
            .bind(host: self.address, port: self.auth_port)

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
