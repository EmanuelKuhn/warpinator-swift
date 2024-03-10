//
//  TransferOp.swift
//  warpinator-project
//
//  Created by Emanuel on 21/03/2022.
//

import Foundation
import UniformTypeIdentifiers

enum TransferOpState: Equatable {
    case initialized
    case requested
    case started
    case failed(reason: String)
    case requestCanceled
    case transferCanceled
    case completed
}

enum Direction {
    case upload
    case download
}

enum TransferOpError: Error {
    case invalidStateToStartTransfer
}

/// Protocol for incoming and outgoing transfers to conform to.
protocol TransferOp: AnyObject {
    var direction: Direction { get }
    
    var localTimestamp: Date { get }
    
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
        
    /// Cancel the operation.
    func cancel() async -> Void
    
    /// Remove the finished operation from the list of transfers.
    func remove() -> Void
    
    var progress: TransferOpMetrics { get }
}

extension TransferOp {
    var state: TransferOpState {
        get { _state.wrappedValue }
        set { _state.wrappedValue = newValue }
    }
    
    fileprivate func cancel(remote: Remote?) {
        if state == .initialized || state == .requested {
            state = .requestCanceled
            
            Task {
                try? await remote?.cancelTransferOpRequest(timestamp: self.timestamp)
            }
        } else if state == .started {
            state = .transferCanceled
            
            Task {
                try? await remote?.stopTransfer(timestamp: self.timestamp)
            }
        }
    }
}

enum TransferOpAvailableActions {
    case acceptOrCancel
    case cancel
    case remove
    case removeOrShow
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
        case .requestCanceled, .transferCanceled, .failed:
            return .remove
        case .completed:
            if self.direction == .download {
                return .removeOrShow
            } else {
                return .remove
            }
        }
    }
}

/// An incoming transfer operation.
class TransferFromRemote: TransferOp {
    let direction: Direction = .download
    
    let localTimestamp: Date = Date(timeIntervalSinceNow: 0)
    
    let timestamp: UInt64
    
    let title: String
    let mimeType: String
    let size: UInt64
    let count: UInt64
    let topDirBasenames: [String]
    
    let _state: MutableObservableValue<TransferOpState>
    
    let progress: TransferOpMetrics
    
    var localSaveUrls: [URL] = []
        
    /// The associated remote. Needed to remove the transferop from the list of transfers.
    private weak var remote: Remote?
    
    lazy var transferDownloader: Result<TransferDownloader, Error> = {
        do {
            return .success(try TransferDownloader(topDirBasenames: self.topDirBasenames, progress: self.progress))
        } catch {
            return .failure(error)
        }
    }()
    
    init(timestamp: UInt64, title: String, mimeType: String, size: UInt64, count: UInt64, topDirBasenames: [String], _state: MutableObservableValue<TransferOpState>, remote: Remote) {
        self.timestamp = timestamp
        self.title = title
        self.mimeType = mimeType
        self.size = size
        self.count = count
        self.topDirBasenames = topDirBasenames
        self._state = _state
        self.remote = remote
        
        self.progress = .init(totalBytesCount: Int(size))
        
    }
    
    func checkIfWillOverwrite() -> Bool {
        switch transferDownloader {
        case .success(let downloader):
            return downloader.checkIfWillOverwrite()
        case .failure(_):
            // If the downloader failed to instantiate, won't overwrite files because the download can't be started.
            return false
        }
    }
    
    func accept() async throws {
        if state == .requested {
            do {
                let downloader = try transferDownloader.get()
                
                try await remote?.startTransfer(transferOp: self, downloader: downloader)
            } catch {
                self.state = .failed(reason: error.localizedDescription)
            }
        }
    }
    
    func cancel() {
        self.cancel(remote: self.remote)
    }
    
    func remove() {
        self.remote?.transfersFromRemote.removeValue(forKey: self.timestamp)
    }
}

extension TransferFromRemote {
    static func createFromRequest(_ request: TransferOpRequest, remote: Remote) -> TransferFromRemote {
        
        return .init(
            timestamp: request.info.timestamp,
            title: request.nameIfSingle,
            mimeType: request.mimeIfSingle,
            size: request.size,
            count: request.count,
            topDirBasenames: request.topDirBasenames,
            _state: .init(.requested),
            remote: remote
        )
    }
    
}


/// An outgoing transfer operation.
class TransferToRemote: TransferOp {
    let direction: Direction = .upload
    
    let localTimestamp: Date = Date(timeIntervalSinceNow: 0)
    
    let timestamp: UInt64
    
    let _state: MutableObservableValue<TransferOpState>
    
    /// The files to transfer.
    let fileProvider: FileProvider
    
    weak var remote: Remote?
    
    let progress: TransferOpMetrics
    
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

    init(timestamp: UInt64, initialState: TransferOpState, fileProvider: FileProvider, remote: Remote?) {
        self.timestamp = timestamp
        self._state = .init(initialState)
        self.fileProvider = fileProvider
        self.remote = remote
        
        self.progress = .init(totalBytesCount: fileProvider.size ?? 0)
    }
    
    func getFileChunks() -> FileChunkSequence {
        return fileProvider.getFileChunks()
    }
    
    func cancel() {
        self.cancel(remote: self.remote)
    }

    func remove() {
        self.remote?.transfersToRemote.removeValue(forKey: timestamp)
    }
}


extension TransferToRemote {
    
    /// Create an outgoing transfer operation from a single file url
    static func fromUrls(urls: [URL], remote: Remote, now: () -> DispatchTime = DispatchTime.now) -> TransferToRemote {
        let files = urls.map { url in
            File(url: url, relativePath: url.lastPathComponent)
        }
        
        let fileProvider = FileProvider(files: files)
        
        return .init(timestamp: now().rawValue, initialState: .initialized, fileProvider: fileProvider, remote: remote)
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
