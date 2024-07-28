//
//  Utils.swift
//  warpinator-project
//
//  Created by Emanuel on 20/03/2022.
//

import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif



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


func openFilesApp(urls: [URL]) {
#if os(macOS)
    // On macOS, a finder window selecting all of the urls can be opened:
    NSWorkspace.shared.activateFileViewerSelecting(urls)
#else
    
    // On iOS, you can only open the files app in a specific directory, but not highlight multiple files:
    var url: URL = urls[0]

    // Find the parent directory of the first file
    if !url.isDirectory {
        url = url.deletingLastPathComponent()
    }
                
    guard let components = NSURLComponents(url: url, resolvingAgainstBaseURL: true) else {
        return
    }

    // Open the files app pointing at the directory
    components.scheme = "shareddocuments"

    if let sharedDocument = components.url {
        print("sharedDocument: \(sharedDocument)")
        
        UIApplication.shared.open(sharedDocument)
    }
#endif
}

extension URL {
    var isDirectory: Bool {
       (try? resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }
    
    var isSymbolicLink: Bool {
        let resourceValues = try? self.resourceValues(forKeys: [.isSymbolicLinkKey])
        return resourceValues?.isSymbolicLink ?? false
    }
}
