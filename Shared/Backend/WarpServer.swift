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


class WarpServer: WarpAsyncProvider {
    
    private enum ServerError: Error {
        case notImplemented
    }
    
    let auth: Auth
    let address: String
    let port: Int
    
    init(auth: Auth) {
        self.auth = auth
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

        // The provider that implements the WarpAsyncProvider protocol
        let provider = self

//        let grpcTLSConfig = GRPCTLSConfiguration.makeServerConfigurationBackedByNetworkFramework(identity: SecIdentity)
        
        // Start the server and print its address once it has started.
        let server = Server.insecure(group: group)
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
    
    func checkDuplexConnection(request: LookupName, context: GRPCAsyncServerCallContext) async throws -> HaveDuplex {
        print("checkDuplexConnection(\(request)")
        
        throw ServerError.notImplemented
    }
    
    func waitingForDuplex(request: LookupName, context: GRPCAsyncServerCallContext) async throws -> HaveDuplex {
        print("waitingForDuplex(\(request)")
        
        throw ServerError.notImplemented

    }
    
    func getRemoteMachineInfo(request: LookupName, context: GRPCAsyncServerCallContext) async throws -> RemoteMachineInfo {
        print("getRemoteMachineInfo(\(request)")
        
        throw ServerError.notImplemented
    }
    
    func getRemoteMachineAvatar(request: LookupName, responseStream: GRPCAsyncResponseStreamWriter<RemoteMachineAvatar>, context: GRPCAsyncServerCallContext) async throws {
        print("getRemoteMachineAvatar(\(request)")
        
        throw ServerError.notImplemented
    }
    
    func processTransferOpRequest(request: TransferOpRequest, context: GRPCAsyncServerCallContext) async throws -> VoidType {
        print("processTransferOpRequest(\(request)")
        
        throw ServerError.notImplemented
    }
    
    func pauseTransferOp(request: OpInfo, context: GRPCAsyncServerCallContext) async throws -> VoidType {
        print("pauseTransferOp(\(request)")
        
        throw ServerError.notImplemented
    }
    
    func startTransfer(request: OpInfo, responseStream: GRPCAsyncResponseStreamWriter<FileChunk>, context: GRPCAsyncServerCallContext) async throws {
        print("startTransfer(\(request)")
        
        throw ServerError.notImplemented
    }
    
    func cancelTransferOpRequest(request: OpInfo, context: GRPCAsyncServerCallContext) async throws -> VoidType {
        print("cancelTransferOpRequest(\(request)")
        
        throw ServerError.notImplemented
    }
    
    func stopTransfer(request: StopInfo, context: GRPCAsyncServerCallContext) async throws -> VoidType {
        print("stopTransfer(\(request)")
        
        throw ServerError.notImplemented
    }
    
    func ping(request: LookupName, context: GRPCAsyncServerCallContext) async throws -> VoidType {
        print("ping(\(request)")
        
        throw ServerError.notImplemented
    }
}

