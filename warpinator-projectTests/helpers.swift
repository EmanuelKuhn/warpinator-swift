//
//  helpers.swift
//  warpinator-projectTests
//
//  Created by Emanuel on 23/04/2022.
//

import Foundation

extension UInt64 {
    static func nanoseconds(milliseconds: UInt64) -> UInt64 {
        return milliseconds * 1000000
    }
}

func getUrlOfTestFile() -> URL {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    
    let filepath = path.appendingPathComponent("test.txt")
    
    try! "Just a text file".write(toFile: filepath.relativeString, atomically: true, encoding: .utf8)
    
    return filepath
}
