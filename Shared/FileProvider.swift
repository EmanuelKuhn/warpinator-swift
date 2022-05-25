//
//  FileProvider.swift
//  warpinator-project
//
//  Created by Emanuel on 09/04/2022.
//

import Foundation

import UniformTypeIdentifiers

class FileProvider {
    
    /// Files in depth first search order.
    /// Such that they can be send in this order, and nested directories can be reconstructed.
    let files: [File]
    
    init(files: [File]) {
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

struct FileChunkSequence : Sequence {
    typealias Element = FileChunk
    
    /// The files in to read and generate FileChunks from.
    /// The files are iterated over in  the order
    let files: [File]
    
    class Iterator : IteratorProtocol {
        
        var fileIterator: IndexingIterator<Array<File>>
        
        
        /// The datachunk iterator of the current file.
        var currentFileChunkIterator: File.ChunkIterator?
        
        init(files: [File]) {
            self.fileIterator = files.makeIterator()
        }
        
        func next() -> FileChunk? {
            
            // Check if async iterator was canceled
            if Task.isCancelled {
                return nil
            }
                        
            // Try to get chunk iterator for next file
            if currentFileChunkIterator == nil {
                let nextFile = fileIterator.next()
                
                currentFileChunkIterator = nextFile?.getDataChunkIterator()
            }
            
            guard let currentFileChunkIterator = currentFileChunkIterator else {
                return nil
            }

            // The current filechunk iterator should have a chunk available
            let chunk: FileChunk = currentFileChunkIterator.next()!
            
            
            // If the current filechunk iterator is exhausted, set reference to nil
            // so that in the next call to next() and iterator for the next file will be made.
            if !currentFileChunkIterator.hasNext() {
                self.currentFileChunkIterator = nil
            }
            
            return chunk
        }
        
        deinit {
            print("deinit FileChunkSequence.Iterator")
        }
    }

    func makeIterator() -> Iterator {
        return Iterator(files: files)
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


struct File {
    
    let url: URL
    
    /// The path that will be transmitted to the reciever.
    let relativePath: String
    
    let chunkSize = 1024 * 1024
    
    init(url: URL, relativePath: String) {
        self.url = url
        self.relativePath = relativePath
    }
    
    internal func getDataChunkIterator() -> ChunkIterator {
        return .init(parent: self)
    }
    
    internal class ChunkIterator: IteratorProtocol {
        
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
                
        init(parent file: File) {
            // Creating the SecurityScopedURL enables accessing a security scoped url until
            // the reference to SecurityScopedURL goes out of scope.
            self.securityScopedURL = SecurityScopedURL(file.url)
            
            self.relativePath = file.relativePath

            self.chunkSize = file.chunkSize
            self.inputStream = .init(url: securityScopedURL.url)!
            
            self.inputStream.open()
            
            self.nextData = readData()
        }
        
        /// Read the next chunk of Data from the inputstream.
        /// Calling this modifies the state of the inputstream.
        private func readData() -> Data? {
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
                
                print(inputStream.streamError)
                
                print(inputStream.streamStatus)
                
                return nil
            }
        }
        
        /// Returns true if iterator has a next FileChunk.
        func hasNext() -> Bool {
            return nextData != nil
        }
        
        /// Get the next FileChunk. Returns nil if there is no next Chunk.
        func next() -> FileChunk? {
            print("inside File.ChunkIterator next()")
            print(inputStream.streamStatus)
            
            guard let currentData = nextData else {
                return nil
            }
            
            let currentChunk = makeFileChunk(data: currentData)
            
            nextData = readData()
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
