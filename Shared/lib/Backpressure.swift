//
//  Backpressure.swift
//  warpinator-project
//
//  Created by Emanuel on 10/04/2022.
//

import Foundation

import GRPC

import NIOCore


import SwiftProtobuf

enum InterceptorError: Error {
    case noPromiseSupplied
}

/// The actor that stores the backpressure metrics for a grpc call (usually a server stream).
/// When calling Backpressure.waitForCompleted(), waitForCompleted waits until enough messages have been transmitted to the client.
/// The amount of messaged that need to be queued for transmission before waitForCompleted waits, is controlled by `cacheMessages`.
actor Backpresure {
    private(set) var numberOfCompletedMessages: Int = 0
    private(set) var numberOfInitiatedMessages: Int = 0
    
    private var callbacks: [(Int)->(Bool)] = []
    
    /// Number of messages that are queued to sent before waitForCompleted() blocks
    let cacheMessages = 2
    
    func incrementCompleted() {
        numberOfCompletedMessages += 1
        
        // Callback return False if resumed and True if should be kept
        callbacks = callbacks.filter {
            $0(numberOfCompletedMessages)
        }
    }
    
    /// Method that suspends until previous messages have been transmitted. If waitForAll == false,
    /// continues after fewer than `cacheMessages` still need to be transmitted. If waitForAll == true,
    /// suspends until all messages have been transmitted.
    func waitForCompleted(waitForAll: Bool) async {
        let currentIndex = numberOfInitiatedMessages
        
        numberOfInitiatedMessages += 1
        
        if numberOfCompletedMessages + self.cacheMessages > currentIndex {
            return
        }
        
        return await withCheckedContinuation { continuation in
                callbacks.append { completedIndex in
                    if (completedIndex + self.cacheMessages > currentIndex) {
                        continuation.resume()
                        
                        return false
                    } else {
                        return true
                    }
                }
        }
    }
}


/// GRPC interceptor that creates and updates context.userInfo.backpressure objects.
class BackPressureInterceptor<Request, Response>: ServerInterceptor<Request, Response> {

    override init() {
        super.init()
        
        print("BackPressureInterceptor.init()")
    }
    
    /// Called when the interceptor has received a response part to handle.
    /// - Parameters:
    ///   - part: The request part which should be sent to the client.
    ///   - promise: A promise which should be completed when the response part has been written.
    ///   - context: An interceptor context which may be used to forward the request part.
    override func send(
      _ part: GRPCServerResponsePart<Response>,
      promise: EventLoopPromise<Void>?,
      context: ServerInterceptorContext<Request, Response>
    ) {
                
        var isMessage: Bool = false
        
        switch part {
        case let .metadata(headers):
          print("> Starting '\(context.path)' RPC, headers: \(headers)")
            
        case let .message(response, metadata):
            
            let r = response as! FileChunk
            print("> Sending response with text '\(r.relativePath)'")
            print("flush: \(metadata.flush)")
            
            
            isMessage = true

        case .end:
            print("> Closing request stream")
        }
        
        var promise = promise
        
        if promise == nil {
            promise = context.eventLoop.makePromise(of: Void.self)
        }
        
        if isMessage {
            let backpressure = context.userInfo.backpressure
            
            promise!.futureResult.whenComplete({ result in
                Task {
                    print("interceptor send Promise completed, \(result)")
                    
                    await backpressure.incrementCompleted()
                }
            })
        }
        
      context.send(part, promise: promise)
    }
}

enum BackPressureKey: UserInfoKey {
    typealias Value = Backpresure
}

extension UserInfo {
    var backpressure: Backpresure {
        mutating get {
            if self[BackPressureKey.self] == nil {
                self[BackPressureKey.self] = Backpresure()
            }
            
            return self[BackPressureKey.self]!
        }
    }
}
