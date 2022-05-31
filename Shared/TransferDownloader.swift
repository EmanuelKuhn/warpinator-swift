//
//  FileDownloadManager.swift
//  warpinator-project
//
//  Created by Emanuel on 31/05/2022.
//

import Foundation

enum WarpFileType: Int32 {
    case file = 1
    case directory = 2
    case symLink = 3
}

enum TransferDownloaderError: Error {
    case unkownFileType
    case invalidTopDirBasenames
    case invalidRelativePath
    case failedCreatingPath
    case timeNotSet
    case symLinksAreNotSupported
}

class TransferDownloader {
    
    let progress: TransferOpMetrics
    
    let topDirBasenames: [String?]
    
    let fileManager: FileManager
    
    let saveDirectory: URL
        
    init(topDirBasenames: [String], progress: TransferOpMetrics) throws {
        
        self.progress = progress
        
        self.fileManager = FileManager.default
        
        self.saveDirectory = try getDocumentsDirectory()
        
        self.topDirBasenames = topDirBasenames.map(TransferDownloader.standardizePath)
        
        guard !self.topDirBasenames.contains(nil) else {
            throw TransferDownloaderError.invalidTopDirBasenames
        }
        
    }
    
    func handleChunk(chunk: FileChunk) throws {
        
        var verbosePrintedChunk = chunk
        verbosePrintedChunk.chunk = Data()
        print(verbosePrintedChunk)

        switch(chunk.fileType) {
        case WarpFileType.file.rawValue:
            try handleFile(chunk: chunk)
        case WarpFileType.directory.rawValue:
            try handleDirectory(chunk: chunk)
        case WarpFileType.symLink.rawValue:
            throw TransferDownloaderError.symLinksAreNotSupported
        default:
            throw TransferDownloaderError.unkownFileType
        }
    }
    
    func handleFile(chunk: FileChunk) throws {
        precondition(chunk.fileType == WarpFileType.file.rawValue)
        
        let fileUrl = try sanitizeRelativePath(relativePath: chunk.relativePath)
        
        if chunk.hasTime {
            let timestamp = NSDate.from(time: chunk.time)

            try chunk.chunk.write(to: fileUrl, options: .atomic)

            try FileManager.default.setAttributes([.modificationDate: timestamp], ofItemAtPath: fileUrl.path)
        } else {
            
            let attributes = try fileManager.attributesOfItem(atPath: fileUrl.path)
            
            let timestamp = attributes[.modificationDate]
            
            try chunk.chunk.append(fileURL: fileUrl)
            
            try FileManager.default.setAttributes([.modificationDate: timestamp], ofItemAtPath: fileUrl.path)
        }

    }

    func handleDirectory(chunk: FileChunk) throws {
        precondition(chunk.fileType == WarpFileType.directory.rawValue)
        
        guard chunk.hasTime else {
            throw TransferDownloaderError.timeNotSet
        }
        
        let timestamp = NSDate.from(time: chunk.time)
        
        let newFolderPath = try self.sanitizeRelativePath(relativePath: chunk.relativePath)
        
        try FileManager.default.createDirectory(at: newFolderPath, withIntermediateDirectories: true, attributes: [.modificationDate: timestamp])
    }
    
    /// Make sure that the relative path doesn't go outside of the save directory and starts with a path component that is in
    /// the list of topDirBasenames.
    ///
    /// Returns standardized path that doesn't contain "/../" etc.
    func sanitizeRelativePath(relativePath: String) throws -> URL {
        guard let relPath = TransferDownloader.standardizePath(path: relativePath) else {
            throw TransferDownloaderError.invalidRelativePath
        }
        
        guard topDirBasenames.contains(URL(string: relPath)?.firstPathComponent) else {
            throw TransferDownloaderError.invalidRelativePath
        }
        
        guard let url = URL(string: relPath, relativeTo: self.saveDirectory) else {
            throw TransferDownloaderError.failedCreatingPath
        }
        
        return url.standardized
    }
    
    static func standardizePath(path: String) -> String? {
        guard let url = URL(string: path) else {
            return nil
        }
        
        let path = url.standardized.path
        
        guard path.count > 0 else {
            return nil
        }
        
        return path
    }
}

extension URL {
    var firstPathComponent: String {
        return self.pathComponents[0]
    }
}


extension NSDate {
    static func from(time: FileTime) -> NSDate {
        // Timestamp is mtime seconds + mtimeUsec microseconds
        return NSDate(timeIntervalSince1970: .init(time.mtime))
                        .addingTimeInterval(.init(time.mtimeUsec) * 10e-6)

    }
}
