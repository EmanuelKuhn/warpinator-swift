//
//  WarpServerProvider.swift
//  warpinator-project
//
//  Created by Emanuel on 18/04/2022.
//

import Foundation

import GRPC

class WarpServerProvider: WarpAsyncProvider {
    
    var interceptors: WarpServerInterceptorFactoryProtocol? = WarpServerInterceptorFactory()
    
    var warpInterceptors: WarpServerInterceptorFactory {
        return interceptors as! WarpServerInterceptorFactory
    }
    
    private enum ServerError: Error {
        case notImplemented
        case remoteNotFound
        case transferOpToRemoteNotFound
    }
    
    let remoteRegistration: RemoteRegistration

    init(remoteRegistration: RemoteRegistration) {
        self.remoteRegistration = remoteRegistration
    }
    
    func checkDuplexConnection(request: LookupName, context: GRPCAsyncServerCallContext) async throws -> HaveDuplex {
        print("checkDuplexConnection(\(request)")
        
        throw ServerError.notImplemented
    }

    func waitingForDuplex(request: LookupName, context: GRPCAsyncServerCallContext) async throws -> HaveDuplex {
        print("waitingForDuplex(\(request)")
        
        // remoteRegistration[id, timeout: 5] waits upto 5 seconds to discover the remote.
        guard let remote = await remoteRegistration[id: request.id, timeout: 5] else {
            print("waitingForDuplex: RemoteNotFound")
            
            print("remotes: \(await remoteRegistration.keys)")
            
            print("Did not find: \(request.id)")
            
            throw ServerError.remoteNotFound
        }
        
        print("waitingForDuplex (\(remote.id)): starting waitForConnected")
        
        await remote.remoteState.waitForConnected()
        
        print("waitingForDuplex (\(remote.id)): finished waitForConnected")
        
        return HaveDuplex.with({
            $0.response = true
        })
    }

    func getRemoteMachineInfo(request: LookupName, context: GRPCAsyncServerCallContext) async throws -> RemoteMachineInfo {
        print("getRemoteMachineInfo(\(request)")
                
        return RemoteMachineInfo.with({
            $0.displayName = "processInfo.fullUserName"
            $0.userName = "processInfo.userName"
        })
    }

    func getRemoteMachineAvatar(request: LookupName, responseStream: GRPCAsyncResponseStreamWriter<RemoteMachineAvatar>, context: GRPCAsyncServerCallContext) async throws {
        print("getRemoteMachineAvatar(\(request)")
        
        throw ServerError.notImplemented
    }

    func processTransferOpRequest(request: TransferOpRequest, context: GRPCAsyncServerCallContext) async throws -> VoidType {
        print("processTransferOpRequest(\(request)")
        
        guard let remote = await remoteRegistration[id: request.info.ident] else {
            throw ServerError.remoteNotFound
        }
        
        let transferOp = TransferFromRemote.createFromRemote(timestamp: request.info.timestamp)
        
        remote.transfersFromRemote.value[request.info.timestamp] = transferOp
        
        // TODO: Currently auto accepts and starts a transfer request
        Task {
            try? await remote.startTransfer(timestamp: transferOp.timestamp)
        }
        
        return VoidType()
    }

    func pauseTransferOp(request: OpInfo, context: GRPCAsyncServerCallContext) async throws -> VoidType {
        print("pauseTransferOp(\(request)")
        
        // Not used in linux warpinator implementation
        throw ServerError.notImplemented
    }

    func startTransfer(request: OpInfo, responseStream: GRPCAsyncResponseStreamWriter<FileChunk>, context: GRPCAsyncServerCallContext) async throws {
        print("startTransfer(\(request)")
        
        guard let remote = await remoteRegistration[id: request.ident] else {
            throw ServerError.remoteNotFound
        }
        
        guard var transferOp = remote.transfersToRemote.value[request.timestamp] else {
            throw ServerError.transferOpToRemoteNotFound
        }
                        
        transferOp.state = .started
        
        let backpressure = context.userInfo.backpressure
        
        for chunk in transferOp.getFileChunks() {
            print("Sending chunk: \(chunk.relativePath), \(chunk.hasTime)")
                        
            try! await responseStream.send(chunk)
            
            
            /// Wait until previous chunks have been transmitted over the network
            await backpressure.waitForCompleted()
        }
                
        print("done sending chunks!")
    }

    func cancelTransferOpRequest(request: OpInfo, context: GRPCAsyncServerCallContext) async throws -> VoidType {
        print("cancelTransferOpRequest(\(request)")
        
        guard let remote = await remoteRegistration[id: request.ident] else {
            throw ServerError.remoteNotFound
        }
        
        guard var transferOp = remote.transfersToRemote.value[request.timestamp] else {
            throw ServerError.transferOpToRemoteNotFound
        }
        
        // TODO: Cancel transferop (as declined)
        
        return VoidType()

    }

    func stopTransfer(request: StopInfo, context: GRPCAsyncServerCallContext) async throws -> VoidType {
        print("stopTransfer(\(request)")
        
        // TODO: Stop transferop
        
        throw ServerError.notImplemented
    }

    func ping(request: LookupName, context: GRPCAsyncServerCallContext) async throws -> VoidType {
        print("ping(\(request)")
        
        return VoidType()
    }

}


