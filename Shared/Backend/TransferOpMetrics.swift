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
