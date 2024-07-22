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
    case invalidStateWhileDownloading
}

enum TransferOpEvent {
    case cancelledByUser
    case requested
    case start
    case failure(reason: String)
    case completed
    case transferCancelledByRemote
    case requestCancelledByRemote
}

/// Protocol for incoming and outgoing transfers to conform to.
protocol TransferOp: AnyObject {
    var direction: Direction { get }
    
    var localTimestamp: Date { get }
    
    /// Timestamp for uniquely identifying the transferop.
    var timestamp: UInt64 { get }
    
    var _state: MutableObservableValue<TransferOpState> { get }
    var state: TransferOpState { get }
    
    // Statemachine will update state based on events
    func tryEvent(event: TransferOpEvent)
    
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

protocol TransferOpFromRemote: TransferOp {
    func checkIfWillOverwrite() -> Bool
    
    func accept() async throws -> Void
}

extension TransferOp {
    var state: TransferOpState {
        get { _state.wrappedValue }
    }
    
    func tryEvent(event: TransferOpEvent, remote: FullRemoteProtocol?) {
        let prevState = state
        
        if let state = nextState(for: event) {
            
            print("Statemachine transition: \(self.state) -> \(state) for event: \(event)")
            
            self._state.wrappedValue = state
            
            enterState(state: state, prevState: prevState, event: event, remote: remote)
        } else {
            print("Statemachine ignored transition: \(self.state) -> \(state) for event: \(event)")
        }
    }
    
    func nextState(for event: TransferOpEvent) -> TransferOpState? {
        switch event {
        case .cancelledByUser:
            switch state {
            case .initialized, .requested:
                return .requestCanceled
            case .started:
                return .transferCanceled
            default:
                return nil
            }
        case .requested:
            switch state {
            case .initialized:
                return .requested
            default:
                return nil
            }
        case .start:
            switch state {
            case .requested:
                return .started
            default:
                return nil
            }
        case .failure(reason: let reason):
            switch state {
            case .requestCanceled, .transferCanceled:
                return nil
            default:
                return .failed(reason: reason)
            }
        case .completed:
            switch state {
            case .started:
                return .completed
            default:
                return nil
            }
        case .transferCancelledByRemote:
            return .transferCanceled
        case .requestCancelledByRemote:
            return .requestCanceled
        }
    }
    
    fileprivate func enterState(state: TransferOpState, prevState: TransferOpState, event: TransferOpEvent, remote: FullRemoteProtocol?) {
        switch state {
        case .initialized:
            return
        case .requested:
            return
        case .started:
            return
        case .failed(_):
            switch prevState {
            case .initialized, .requested:
                Task {
                    try? await remote?.cancelTransferOpRequest(timestamp: self.timestamp)
                }
            case .started:
                Task {
                    try? await remote?.stopTransfer(timestamp: self.timestamp, error: true)
                }
            default:
                break
            }
            return
        case .requestCanceled:
            switch event {
            case .transferCancelledByRemote, .requestCancelledByRemote:
                return
            default:
                Task {
                    try? await remote?.cancelTransferOpRequest(timestamp: self.timestamp)
                }
            }
        case .transferCanceled:
            switch event {
            case .transferCancelledByRemote, .requestCancelledByRemote:
                return
            default:
                Task {
                    try? await remote?.stopTransfer(timestamp: self.timestamp, error: false)
                }
            }
        case .completed:
            return
        }
    }
    
    func cancel() {
        tryEvent(event: .cancelledByUser)
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
class TransferFromRemote: TransferOpFromRemote {
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
    private weak var remote: FullRemoteProtocol?
    
    lazy var transferDownloader: Result<TransferDownloader, Error> = {
        do {
            return .success(try TransferDownloader(topDirBasenames: self.topDirBasenames, progress: self.progress, fileCount: self.count))
        } catch {
            return .failure(error)
        }
    }()
    
    init(timestamp: UInt64, title: String, mimeType: String, size: UInt64, count: UInt64, topDirBasenames: [String], initialState: TransferOpState, remote: FullRemoteProtocol) {
        self.timestamp = timestamp
        self.title = title
        self.mimeType = mimeType
        self.size = size
        self.count = count
        self.topDirBasenames = topDirBasenames
        self._state = .init(initialState)
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
                self.tryEvent(event: .failure(reason: error.localizedDescription))
            }
        }
    }
    
    func remove() {
        self.remote?.transfersFromRemote.removeValue(forKey: self.timestamp)
    }
    
    func tryEvent(event: TransferOpEvent) {
        self.tryEvent(event: event, remote: remote)
    }
}

extension TransferFromRemote {
    static func createFromRequest(_ request: TransferOpRequest, remote: FullRemoteProtocol) -> TransferFromRemote {
        
        return .init(
            timestamp: request.info.timestamp,
            title: request.nameIfSingle,
            mimeType: request.mimeIfSingle,
            size: request.size,
            count: request.count,
            topDirBasenames: request.topDirBasenames,
            initialState: .requested,
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
    
    weak var remote: FullRemoteProtocol?
    
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
    
    init(timestamp: UInt64, initialState: TransferOpState, fileProvider: FileProvider, remote: FullRemoteProtocol?) {
        self.timestamp = timestamp
        self._state = .init(initialState)
        self.fileProvider = fileProvider
        self.remote = remote
        
        self.progress = .init(totalBytesCount: fileProvider.size ?? 0)
    }
    
    func getFileChunks() -> FileChunkSequence {
        return fileProvider.getFileChunks()
    }
    
    func remove() {
        self.remote?.transfersToRemote.removeValue(forKey: timestamp)
    }
    
    func tryEvent(event: TransferOpEvent) {
        self.tryEvent(event: event, remote: remote)
    }
}


extension TransferToRemote {
    static func fromUrls(urls: [URL], remote: Remote, now: () -> DispatchTime = DispatchTime.now) -> TransferToRemote {
        let files = urls.map { url in
            FileItemFactory.from(url: url, relativePath: url.lastPathComponent)
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
