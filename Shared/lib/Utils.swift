//
//  Utils.swift
//  warpinator-project
//
//  Created by Emanuel on 20/03/2022.
//

import Foundation

extension Data {
    var bytes: [UInt8] {
        return [UInt8](self)
    }
}

enum FileError: Error {
    case failedToOpenFileHandle
}

extension Data {
    func append(fileURL: URL) throws {
        guard let fileHandle = FileHandle(forWritingAtPath: fileURL.path) else {
            throw FileError.failedToOpenFileHandle
        }
        
        defer {
            fileHandle.closeFile()
        }
        
        fileHandle.seekToEndOfFile()
        fileHandle.write(self)
    }
}

func getDocumentsDirectory() throws -> URL {
        let rootFolderURL = try FileManager.default.url(
                    for: .documentDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: false
                )

        return rootFolderURL
    }
