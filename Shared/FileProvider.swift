//
//  FileProvider.swift
//  warpinator-project
//
//  Created by Emanuel on 09/04/2022.
//

import Foundation

import UniformTypeIdentifiers

protocol FileItem {
    func getDataChunkIterator() throws -> ChunkIterator
    
    var relativePath: String { get }
    var url: URL { get }
}

struct FileItemFactory {
    static func from(url: URL, relativePath: String) -> FileItem {
        if url.isDirectory {
            return Folder(url: url, relativePath: relativePath)
        }
        else {
            return File(url: url, relativePath: relativePath)
        }
    }
}

protocol ChunkIterator {
    func next() throws -> FileChunk?
    func hasNext() -> Bool
}

class FileProvider {
    
    /// Files in depth first search order.
    /// Such that they can be send in this order, and nested directories can be reconstructed.
    let files: [FileItem]
    
    init(files: [FileItem]) {
        self.files = files
    }
    
    func getFileChunks() -> FileChunkSequence {
        return FileChunkSequence(files: files)
    }
    
    var nameIfSingle: String {
        if files.count == 1 {
            return files[0].relativePath
        } else {
            return "\(files.count) files"
        }
    }
    
    var mimeIfSingle: String {
        if files.count == 1 {
            return (files[0].url.mime() ?? UTType.data).mimeTypeString
        } else {
            return "application/octet-stream"
        }
    }
    
    var size: Int? {
        return files.map {
            $0.url.fileSize()
        }.reduce(0) { prev, next in
            if let prev = prev, let next = next {
                return prev + next
            } else {
                return nil
            }
        }
    }
    
    var count: Int {
        return files.count
    }
    
    var topDirBasenames: [String] {
        return files.map {
            $0.relativePath
        }
    }
}

extension UTType {
    var mimeTypeString: String {
        if let mimeType = self.preferredMIMEType {
            return mimeType
        } else {
            return "application/octet-stream"
        }
    }
}

enum FileProviderError: Error {
    case failedToReadFileChunk
}

struct FileChunkSequence : Sequence {
    typealias Element = Result<FileChunk, Error>
    
    /// The files in to read and generate FileChunks from.
    /// The files are iterated over in  the order
    let files: [FileItem]
    
    func makeIterator() -> Iterator {
        return Iterator(files: files)
    }
    
    class Iterator : IteratorProtocol {
        
        var fileIterator: IndexingIterator<Array<FileItem>>
        
        
        /// The datachunk iterator of the current file.
        var currentFileChunkIterator: ChunkIterator?
        
        init(files: [FileItem]) {
            self.fileIterator = files.makeIterator()
        }
        
        func next() -> Result<FileChunk, Error>? {
            
            // Check if async iterator was canceled
            if Task.isCancelled {
                
                // Propagate Task cancellation
                return .failure(CancellationError())
            }
                        
            // Try to get chunk iterator for next file
            if currentFileChunkIterator == nil {
                let nextFile = fileIterator.next()
                
                do {
                    currentFileChunkIterator = try nextFile?.getDataChunkIterator()
                } catch {
                    return .failure(FileProviderError.failedToReadFileChunk)
                }
            }
            
            
            // Finished iterating
            guard let currentFileChunkIterator = currentFileChunkIterator else {
                return nil
            }

            // The current filechunk iterator should have a chunk available
            guard let chunk: FileChunk = try? currentFileChunkIterator.next() else {
                return .failure(FileProviderError.failedToReadFileChunk)
            }
            
            
            // If the current filechunk iterator is exhausted, set reference to nil
            // so that in the next call to next() and iterator for the next file will be made.
            if !currentFileChunkIterator.hasNext() {
                self.currentFileChunkIterator = nil
            }
            
            return .success(chunk)
        }
        
        deinit {
            print("deinit FileChunkSequence.Iterator")
        }
    }
}




/// Use the reference counter to automatically start and stop accessing a security scoped url.
class SecurityScopedURL {

    let url: URL

    init(_ url: URL) {
        self.url = url

        url.startAccessingSecurityScopedResource()
    }
    
    deinit {
        print("Deinit SecurityScopedURL(\(url)")
        
        url.stopAccessingSecurityScopedResource()
    }
}


struct File: FileItem {
    
    let url: URL
    
    /// The path that will be transmitted to the reciever.
    let relativePath: String
    
    let chunkSize = 1024 * 1024
    
    init(url: URL, relativePath: String) {
        self.url = url
        self.relativePath = relativePath
    }
    
    internal func getDataChunkIterator() throws -> ChunkIterator {
        return try FileChunkIterator(parent: self)
    }
    
    internal class FileChunkIterator: ChunkIterator {
        
        typealias Element = FileChunk
        
        /// The file is split into chunks of chunkSize
        private let chunkSize: Int
        
        /// The inputstream used to read data chunks from.
        private let inputStream: InputStream
        
        /// When getting chunks, URL.startAccessingSecurityScopedResource needs to be called,
        /// and wrapping in SecurityScopedURL handles this.
        private let securityScopedURL: SecurityScopedURL
        
        private var url: URL {
            securityScopedURL.url
        }
        
        private var relativePath: String
        
        /// Cache the next Data chunk in order to enable checking hasNext.
        private var nextData: Data?
        
        /// Boolean indiciating if the next chunk is the first FileChunk.
        /// Is set to false after next() returns the first chunk.
        /// The first FileChunk will have its time field set.
        private var isFirstChunk: Bool = true
                
        init(parent file: File) throws {
            // Creating the SecurityScopedURL enables accessing a security scoped url until
            // the reference to SecurityScopedURL goes out of scope.
            self.securityScopedURL = SecurityScopedURL(file.url)
            
            self.relativePath = file.relativePath

            self.chunkSize = file.chunkSize
            self.inputStream = .init(url: securityScopedURL.url)!
            
            self.inputStream.open()
            
            self.nextData = try readData()
        }
        
        /// Read the next chunk of Data from the inputstream.
        /// Calling this modifies the state of the inputstream.
        private func readData() throws -> Data? {
            let bufferPointer: UnsafeMutablePointer<UInt8> = .allocate(capacity: chunkSize)

            defer {
                bufferPointer.deallocate()
            }
            
            let read = inputStream.read(bufferPointer, maxLength: chunkSize)

            if read > 0 {
                print("inside File.ChunkIterator readData(): read=\(read)")

                var data = Data()

                data.append(bufferPointer, count: read)

                return data
            } else {
                
                print("inside File.ChunkIterator readData(): read=\(read); return nil")
                
                if let error = inputStream.streamError {
                    print(inputStream.streamError)

                    throw error
                }

                print(inputStream.streamStatus)
                
                return nil
            }
        }
        
        /// Returns true if iterator has a next FileChunk.
        func hasNext() -> Bool {
            return nextData != nil
        }
        
        /// Get the next FileChunk. Returns nil if there is no next Chunk.
        func next() throws -> FileChunk? {
            print("inside File.ChunkIterator next()")
            print(inputStream.streamStatus)
            
            guard let currentData = nextData else {
                return nil
            }
            
            let currentChunk = makeFileChunk(data: currentData)
            
            nextData = try readData()
            isFirstChunk = false
            
            return currentChunk
        }
        
        /// Create a FileChunk from a read data Chunk.
        private func makeFileChunk(data: Data) -> FileChunk {
            if isFirstChunk {
                
                let mTime = self.url.contentModificationDate()?.timeIntervalSince1970 ?? 0
                
                let fileTime = FileTime.with({
                    $0.mtime = UInt64(mTime)
                    $0.mtimeUsec = UInt32(mTime.truncatingRemainder(dividingBy: 1) * 10e6)
                })
                
                return FileChunk.with({
                    $0.chunk = data
                    $0.relativePath = self.relativePath
                    $0.fileType = 1
                    $0.fileMode = 420
                    $0.time = fileTime
                })
                
            } else {
                return FileChunk.with({
                    $0.chunk = data
                    $0.relativePath = self.relativePath
                    $0.fileType = 1
                    $0.fileMode = 420
                })
            }
        }
        
        deinit {
            print("deinit File.ChunkIterator")
            
            self.inputStream.close()
        }
    }
}

struct Folder: FileItem {
    
    let url: URL
    
    /// The path that will be transmitted to the reciever.
    let relativePath: String
    
    let chunkSize = 1024 * 1024
    
    let fileManager = FileManager.default
    
    init(url: URL, relativePath: String) {
        self.url = url
        self.relativePath = relativePath
    }
    
    internal func getDataChunkIterator() throws -> ChunkIterator {
        return try FolderChunkIterator(parent: self, fileManager: fileManager)
    }
    
    internal class FolderChunkIterator: ChunkIterator {
        
        typealias Element = FileChunk
        
        private let securityScopedURL: SecurityScopedURL
        
        private var url: URL {
            securityScopedURL.url
        }
        
        private var relativePath: String
        
        private var isFirstChunk: Bool = true
        
        private var children: [FileItem]
        
        private var currentChildIterator: ChunkIterator? = nil
                
        init(parent folder: Folder, fileManager: FileManager) throws {
            self.securityScopedURL = SecurityScopedURL(folder.url)
            self.relativePath = folder.relativePath
            
            let url = securityScopedURL.url
            
            let childPaths: [URL] = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.totalFileSizeKey])
            
            // Recursively find children
            self.children = childPaths.map({FileItemFactory.from(url: $0, relativePath: "\(folder.relativePath)/\($0.lastPathComponent)")})
        }
        
        func hasNext() -> Bool {
            
            // Still have to send FileChunk representing this folder
            if isFirstChunk {
                return true
            }
            
            // Still have children to iterate over
            if !self.children.isEmpty {
                return true
            }
            
            // Last child still has chunks left
            if let currentChildIterator = currentChildIterator {
                return currentChildIterator.hasNext()
            }
            
            // Done
            return false
        }
        
        /// Get the next FileChunk. Returns nil if there is no next Chunk.
        func next() throws -> FileChunk? {
            let currentChunk: FileChunk?
            
            if isFirstChunk {
                // Return chunk representing this folder
                
                currentChunk = makeFolderChunk()
                
                isFirstChunk = false
            } else {
                // Try iterating over children
                
                let chunk = try self.currentChildIterator?.next()
                
                if let chunk = chunk {
                    currentChunk = chunk
                } else {
                    if !self.children.isEmpty {
                        let nextFileItem = self.children.removeFirst()
                        
                        self.currentChildIterator = try nextFileItem.getDataChunkIterator()

                        if let currentChildIterator = self.currentChildIterator {
                            
                            print(nextFileItem)
                            
                            print(nextFileItem.relativePath)
                            print(nextFileItem.url)
                            
                            assert(currentChildIterator.hasNext(), "Assume if there is a next currentChildIterator, then the first call will always return a filechunk, but \(nextFileItem), \(nextFileItem.relativePath)")
                            
                            currentChunk = try currentChildIterator.next()
                        } else {
                            currentChunk = nil
                        }
                    } else {
                        // No more children to iterate over
                        currentChunk = nil
                        
                        assert(self.hasNext() == false, "now really shouldn't have more chunks right?")

                    }
                }
            }
            
            if currentChunk == nil {
                // if currentChunk is nil here, that should mean that we iterated over all the children
                print(self.currentChildIterator?.hasNext())
                
                assert(self.hasNext() == false, "It should be the case that hasNext() returns false when next() is going to return nil")
            }

            return currentChunk
        }
        
        /// Create a FileChunk from a read data Chunk.
        private func makeFolderChunk() -> FileChunk {
            assert(isFirstChunk, "This (makeFolderChunk()) should only get called once for each folder")
            
                
            let mTime = self.url.contentModificationDate()?.timeIntervalSince1970 ?? 0
            
            let fileTime = FileTime.with({
                $0.mtime = UInt64(mTime)
                $0.mtimeUsec = UInt32(mTime.truncatingRemainder(dividingBy: 1) * 10e6)
            })
            
            return FileChunk.with({
                $0.relativePath = self.relativePath
                $0.fileType = WarpFileType.directory.rawValue
                $0.fileMode = 509
                $0.time = fileTime
            })
        }
    }
}
