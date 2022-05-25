//
//  WarpServerInterceptors.swift
//  warpinator-project
//
//  Created by Emanuel on 19/04/2022.
//

import Foundation

import GRPC

class WarpServerInterceptorFactory: WarpServerInterceptorFactoryProtocol {
    
    let startTransferBackpressure = BackPressureInterceptor<OpInfo, FileChunk>()
    
    let transferOpMetricsInterceptor = TransferOpMetricsInterceptor<OpInfo>()
    
    init() {
        print("WarpServerInterceptorFactory.init()")
    }
    
    func makeCheckDuplexConnectionInterceptors() -> [ServerInterceptor<LookupName, HaveDuplex>] {
        return []
    }
    
    func makeWaitingForDuplexInterceptors() -> [ServerInterceptor<LookupName, HaveDuplex>] {
        return []
    }
    
    func makeGetRemoteMachineInfoInterceptors() -> [ServerInterceptor<LookupName, RemoteMachineInfo>] {
        return []
    }
    
    func makeGetRemoteMachineAvatarInterceptors() -> [ServerInterceptor<LookupName, RemoteMachineAvatar>] {
        return []
    }
    
    func makeProcessTransferOpRequestInterceptors() -> [ServerInterceptor<TransferOpRequest, VoidType>] {
        return []
    }
    
    func makePauseTransferOpInterceptors() -> [ServerInterceptor<OpInfo, VoidType>] {
        return []
    }
    
    func makeStartTransferInterceptors() -> [ServerInterceptor<OpInfo, FileChunk>] {
        
        print("makeStartTransferInterceptors")
        
        return [startTransferBackpressure, transferOpMetricsInterceptor]
    }
    
    func makeCancelTransferOpRequestInterceptors() -> [ServerInterceptor<OpInfo, VoidType>] {
        return []
    }
    
    func makeStopTransferInterceptors() -> [ServerInterceptor<StopInfo, VoidType>] {
        return []
    }
    
    func makePingInterceptors() -> [ServerInterceptor<LookupName, VoidType>] {
        return []
    }
    
    
}
