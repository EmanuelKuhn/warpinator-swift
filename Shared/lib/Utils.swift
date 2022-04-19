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

extension Data {
    @discardableResult
    func append(fileURL: URL) throws -> Bool {
        if let fileHandle = FileHandle(forWritingAtPath: fileURL.path) {
            defer {
                fileHandle.closeFile()
            }
            fileHandle.seekToEndOfFile()
            fileHandle.write(self)
            
            return true
        } else {
            return false
        }
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
