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

enum Direction {
    case upload
    case download
}

/// Protocol for incoming and outgoing transfers to conform to.
protocol TransferOp {
    var direction: Direction { get }
    
    /// Timestamp for uniquely identifying the transferop.
    var timestamp: UInt64 { get }
    
    var _state: MutableObservableValue<TransferOpState> { get }
    var state: TransferOpState { get set }

    /// A title describing the files that will be transfered.
    var title: String { get }
    
    /// Mimetype describing the files that will be transfered.
    var mimeType: String { get }
    
    /// String indicating the size of the files that will be transfered.
    var size: UInt64 { get }
    
    /// The number of files transfered
    var count: UInt64 { get }
    
    /// The names of the top level directories.
    var topDirBasenames: [String] { get }
}

extension TransferOp {
    var state: TransferOpState {
        get { _state.wrappedValue }
        set { _state.wrappedValue = newValue }
    }
}

enum TransferOpAvailableActions {
    case acceptOrCancel
    case cancel
    case remove
}

extension TransferOp {
    /// Which actions are currently available.
    var availableActions: TransferOpAvailableActions {
        switch(self.state) {
        case .requested:
            if self.direction == .download {
                return .acceptOrCancel
            } else {
                return .cancel
            }
        case .initialized, .started:
            return .cancel
        case .canceled, .failed:
            return .remove
        }
    }
}

/// An incoming transfer operation.
struct TransferFromRemote: TransferOp {
    
    let direction: Direction = .download
    
    let timestamp: UInt64
    
    let title: String
    let mimeType: String
    let size: UInt64
    let count: UInt64
    let topDirBasenames: [String]
    
    let _state: MutableObservableValue<TransferOpState>
}

extension TransferFromRemote {
    static func createFromRequest(_ request: TransferOpRequest) -> TransferFromRemote {
        
        return .init(
            timestamp: request.info.timestamp,
            title: request.nameIfSingle,
            mimeType: request.mimeIfSingle,
            size: request.size,
            count: request.count,
            topDirBasenames: request.topDirBasenames,
            _state: .init(.requested)
        )
    }
    
}


/// An outgoing transfer operation.
struct TransferToRemote: TransferOp {
    let direction: Direction = .upload
    
    let timestamp: UInt64
    
    let _state: MutableObservableValue<TransferOpState>
    
    /// The files to transfer.
    let fileProvider: FileProvider
    
    var title: String {
        fileProvider.nameIfSingle
    }
    
    var mimeType: String {
        fileProvider.mimeIfSingle
    }
    
    var size: UInt64 {
        if let size = fileProvider.size {
            return UInt64(size)
        } else {
            return 0
        }
    }
    
    var count: UInt64 {
        return UInt64(fileProvider.count)
    }
    
    var topDirBasenames: [String] {
        return fileProvider.topDirBasenames
    }

    init(timestamp: UInt64, initialState: TransferOpState, fileProvider: FileProvider) {
        self.timestamp = timestamp
        self._state = .init(initialState)
        self.fileProvider = fileProvider
    }
    
    func getFileChunks() -> FileChunkSequence {
        return fileProvider.getFileChunks()
    }
}


extension TransferToRemote {
    
    /// Create an outgoing transfer operation from a single file url
    static func fromUrls(urls: [URL], now: () -> DispatchTime = DispatchTime.now) -> TransferToRemote {
        let files = urls.map { url in
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
