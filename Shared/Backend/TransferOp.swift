//
//  TransferOp.swift
//  warpinator-project
//
//  Created by Emanuel on 21/03/2022.
//

import Foundation
import UniformTypeIdentifiers

enum TransferOpState {
    case initialized
    case requested
    case started
    case failed
    case canceled
}

/// Protocol for incoming and outgoing transfers to conform to.
protocol TransferOp {
    
    /// Timestamp for uniquely identifying the transferop.
    var timestamp: UInt64 { get }
    
    var state: TransferOpState { get set }
    
//    func cancel()
}

/// An incoming transfer operation.
struct TransferFromRemote: TransferOp {
    
    let timestamp: UInt64
    
    var state: TransferOpState
    
    init(timestamp: UInt64, initialState: TransferOpState) {
        self.timestamp = timestamp
        self.state = initialState
    }
    
    static func createFromRemote(timestamp: UInt64) -> TransferFromRemote {
        return .init(timestamp: timestamp, initialState: .requested)
    }
}


/// An outgoing transfer operation.
struct TransferToRemote: TransferOp {
    
    let timestamp: UInt64
    
    var state: TransferOpState
    
    /// The files to transfer.
    let fileProvider: FileProvider
    
    init(timestamp: UInt64, initialState: TransferOpState, fileProvider: FileProvider) {
        self.timestamp = timestamp
        self.state = initialState
        self.fileProvider = fileProvider
    }
    
    func getFileChunks() -> FileChunkSequence {
        return fileProvider.getFileChunks()
    }
}


extension TransferToRemote {
    
    /// Create an outgoing transfer operation from a single file url
    static func fromUrl(url: URL, now: () -> DispatchTime = DispatchTime.now) -> TransferToRemote {
        let files = [url].map { url in
            File(url: url, relativePath: url.lastPathComponent)
        }
        
        let fileProvider = FileProvider(files: files)
        
        return .init(timestamp: now().rawValue, initialState: .initialized, fileProvider: fileProvider)
    }
}

extension URL {
    
    func fileSize() -> Int? {
        self.startAccessingSecurityScopedResource()
        
        defer {
            self.stopAccessingSecurityScopedResource()
        }
        
        let resourceValues = try? self.resourceValues(forKeys: [.fileSizeKey])
        
        return resourceValues?.fileSize
    }
    
    func mime() -> UTType? {
        let resourceValues = try? self.resourceValues(forKeys: [.contentTypeKey])
        
        return resourceValues?.contentType
    }
    
    func contentModificationDate() -> Date? {
        let resourceValues = try? self.resourceValues(forKeys: [.contentModificationDateKey])
        
        return resourceValues?.contentModificationDate
        
    }
}
