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
        case transferCanceled
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
        
        await remote.waitForConnected()
        
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
        
        let transferOp = TransferFromRemote.createFromRequest(request, remote: remote)
        
        remote.transfersFromRemote[request.info.timestamp] = transferOp
                
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
        
        guard var transferOp = remote.transfersToRemote[request.timestamp] else {
            throw ServerError.transferOpToRemoteNotFound
        }
        
        guard transferOp.state == .requested else {
            throw ServerError.transferCanceled
        }
                        
        transferOp.state = .started
        
        let backpressure = context.userInfo.backpressure
        
        for chunk in transferOp.getFileChunks() {
            
            if transferOp.state != .started {
                throw ServerError.transferCanceled
            }
            
            print("Sending chunk: \(chunk.relativePath), \(chunk.hasTime)")
                        
            try! await responseStream.send(chunk)
            
            
            // Suspend until enough previous chunks have been transmitted over the network.
            await backpressure.waitForCompleted(waitForAll: false)
        }
        
        // Suspend until all chunks have been transmitted.
        await backpressure.waitForCompleted(waitForAll: true)
        
        transferOp.state = .completed
        
        print("done sending chunks!")
    }

    func cancelTransferOpRequest(request: OpInfo, context: GRPCAsyncServerCallContext) async throws -> VoidType {
        print("cancelTransferOpRequest(\(request)\n")
        
        guard let remote = await remoteRegistration[id: request.ident] else {
            throw ServerError.remoteNotFound
        }
        
        print("cancelTransferOpRequest: found remote\n")
        
        let transferOps = remote.transferOps(forKey: request.timestamp)
        
        guard transferOps.count > 0 else {
            throw ServerError.transferOpToRemoteNotFound
        }
        
        transferOps.forEach {
            $0.state = .requestCanceled
        }
        
        return VoidType()

    }

    func stopTransfer(request: StopInfo, context: GRPCAsyncServerCallContext) async throws -> VoidType {
        print("stopTransfer(\(request)")
        
        let info = request.info
        
        guard let remote = await remoteRegistration[id: info.ident] else {
            throw ServerError.remoteNotFound
        }
        
        let transferOps = remote.transferOps(forKey: info.timestamp)
        
        guard transferOps.count > 0 else {
            throw ServerError.transferOpToRemoteNotFound
        }
        
        transferOps.forEach {
            $0.state = .transferCanceled
        }

        return VoidType()
    }

    func ping(request: LookupName, context: GRPCAsyncServerCallContext) async throws -> VoidType {
        print("ping(\(request)")
        
        return VoidType()
    }

}


