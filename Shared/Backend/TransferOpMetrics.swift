//
//  TransferOpMetricsInterceptor.swift
//  warpinator-project
//
//  Created by Emanuel on 25/05/2022.
//

import Foundation

import GRPC
import NIO

/// Class for keeping track of the progress of a transfer operation.
class TransferOpMetrics: ObservableObject {
    
    let totalBytesCount: Int
    
    @Published
    private(set) var bytesTransmittedCount: Int = 0 {
        willSet {
            print("Progress bytesTransmittedCount willset: \(bytesTransmittedCount) -> \(newValue), total: \(totalBytesCount)")
        }
    }
    
    private(set) var transmittedChunkCount: Int = 0
    
    init(totalBytesCount: Int) {
        self.totalBytesCount = totalBytesCount
    }
    
    @MainActor
    func increment(by bytesCount: Int) {
        self.transmittedChunkCount += 1
        self.bytesTransmittedCount += bytesCount
    }
}

/// MARK: TransferOpMetricsInterceptor for transfers to remote.

/// Interceptor that increments metrics counters whenever a filechunk is transmitted.
class TransferOpMetricsInterceptor<Request>: ServerInterceptor<Request, FileChunk> {
    
    override init() {
        super.init()
        
        print("TransferOpMetricsInterceptor.init()")
    }
    
    /// Called when the interceptor has received a response part to handle.
    /// - Parameters:
    ///   - part: The request part which should be sent to the client.
    ///   - promise: A promise which should be completed when the response part has been written.
    ///   - context: An interceptor context which may be used to forward the request part.
    override func send(
        _ part: GRPCServerResponsePart<FileChunk>,
        promise: EventLoopPromise<Void>?,
        context: ServerInterceptorContext<Request, FileChunk>
    ) {
        
        print("transferopmetrics: send()")
        
        let promise = promise ?? context.eventLoop.makePromise(of: Void.self)
        
        if case let .message(filechunk, _) = part {
            
            print("transferopmetrics: message")
            
            let metrics = context.userInfo.filechunkMetrics
            
            let bytesCount = filechunk.chunk.count
            
            promise.futureResult.whenComplete({ result in
                Task {
                    print("metrics interceptor send Promise completed, \(result)")
                    
                    await metrics!.increment(by: bytesCount)
                }
            })
        }
        
        context.send(part, promise: promise)
    }
}

enum FileChunkMetricsKey: UserInfoKey {
    typealias Value = TransferOpMetrics
}


extension UserInfo {
    var filechunkMetrics: TransferOpMetrics? {
        get {
            return self[FileChunkMetricsKey.self]
        }
        
        set {
            self[FileChunkMetricsKey.self] = newValue
        }
    }
}
