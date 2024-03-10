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
    
    let topDirBasenames: [String]
    
    let fileManager: FileManager
    
    let saveDirectory: URL
    
    var seenRelativePaths: Set<String>
    
        
    init(topDirBasenames: [String], progress: TransferOpMetrics) throws {
        
        self.progress = progress
        
        self.fileManager = FileManager.default
        
        self.saveDirectory = try getDocumentsDirectory()
        
        self.topDirBasenames = try topDirBasenames.map(TransferDownloader.sanitizeTopDirName)
        
        self.seenRelativePaths = Set()
    }
    
    /// The local paths the topDirBasenames will be downloaded to. This is computed by computing the local save path for each sanitized topDirBaseName given the self.saveDirectory
    lazy var saveURLs: [URL] = {
        let saveURLs = try? topDirBasenames.map { baseName in
            try sanitizeRelativePath(relativePath: baseName).absoluteURL
        }
        
        guard let saveURLs = saveURLs else {
            return []
        }
        
        return saveURLs
    }()
    
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
        
        // If this is the first chunk of fileUrl
        if !self.seenRelativePaths.contains(chunk.relativePath) {
            self.seenRelativePaths.update(with: chunk.relativePath)

            try chunk.chunk.write(to: fileUrl, options: .atomic)

            // The first chunk should have timestamp
            if chunk.hasTime {
                let timestamp = NSDate.from(time: chunk.time)
                try FileManager.default.setAttributes([.modificationDate: timestamp], ofItemAtPath: fileUrl.path)
            }
        } else {
            // Read the current modification date
            let attributes = try fileManager.attributesOfItem(atPath: fileUrl.path)
            let timestamp = attributes[.modificationDate]
            
            try chunk.chunk.append(fileURL: fileUrl)

            // Keep the modification date
            try FileManager.default.setAttributes([.modificationDate: timestamp as Any], ofItemAtPath: fileUrl.path)
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
        
        guard let escapedRelPath = relPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw TransferDownloaderError.invalidRelativePath
        }
        
        let firstPathComponent = URL(string: escapedRelPath)?.firstPathComponent
        
        guard firstPathComponent != nil && topDirBasenames.contains(firstPathComponent!) else {
            throw TransferDownloaderError.invalidRelativePath
        }
        
        guard let url = URL(string: escapedRelPath, relativeTo: self.saveDirectory) else {
            throw TransferDownloaderError.failedCreatingPath
        }
        
        return url.standardized
    }
    
    static func standardizePath(path: String) -> String? {
        
        let escapedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        
        guard let url = URL(string: escapedPath ?? "") else {
            return nil
        }
        
        let path = url.standardized.path
        
        guard path.count > 0 else {
            return nil
        }
        
        return path
    }
    
    /// Interprets the topDirName as URL and asserts that it has exactly one path component.
    ///
    /// Returns the sanitized name.
    static func sanitizeTopDirName(dirName: String) throws -> String {
        let escapedPath = dirName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        
        guard let url = URL(string: escapedPath ?? "")?.standardized else {
            throw TransferDownloaderError.invalidTopDirBasenames
        }
        
        guard url.pathComponents.count == 1 else {
            throw TransferDownloaderError.invalidTopDirBasenames
        }
        
        return url.path
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
