//
//  TransferDownloaderTests.swift
//  warpinator-project
//
//  Created by Emanuel on 31/05/2022.
//

import XCTest
@testable import warpinator_project

class TransferDownloaderTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testSanitizeRelativePathCanHandleSpaces() throws {
        let relpath = "versions/solution (copy).ipynb"
        
        let downloader = try TransferDownloader(topDirBasenames: ["versions"], progress: TransferOpMetrics(totalBytesCount: 100))
        
        let result = try downloader.sanitizeRelativePath(relativePath: relpath)
        
        XCTAssertEqual(relpath, result.relativePath)
        
    }

    func testTopDirBasenamesCanHaveSpaces() throws {
        let downloader = try TransferDownloader(topDirBasenames: ["top dir name with spaces"], progress: TransferOpMetrics(totalBytesCount: 100))
        
        XCTAssertNotNil(downloader)
    }
    
    func testTopDirBasenamesCannotHaveMultipleComponents() throws {
        
        XCTAssertThrowsError(
            try TransferDownloader(topDirBasenames: ["nested/folder/"], progress: TransferOpMetrics(totalBytesCount: 100))
        )
    }

    func testTopDirBasenamesCannotHaveLinksToParentDir() throws {
        
        XCTAssertThrowsError(
            try TransferDownloader(topDirBasenames: [".."], progress: TransferOpMetrics(totalBytesCount: 100))
        )
    }

    func testTopDirBasenamesCannotBeEmpty() throws {
        
        XCTAssertThrowsError(
            try TransferDownloader(topDirBasenames: ["hey", ""], progress: TransferOpMetrics(totalBytesCount: 100))
        )
    }
    
    func testTopDirBasenamesCannotPointToRandomPath() throws {
        
        XCTAssertThrowsError(
            try TransferDownloader(topDirBasenames: ["/Users/throwaway/Downloads"], progress: TransferOpMetrics(totalBytesCount: 100))
        )
    }
    
    
    func testRelativeNameHasToStartWithTopDirName() throws {
        
        let relpath = "solution (copy).ipynb"
        
        let downloader = try TransferDownloader(topDirBasenames: ["versions", "hello"], progress: TransferOpMetrics(totalBytesCount: 100))

        XCTAssertThrowsError(
            try downloader.sanitizeRelativePath(relativePath: relpath)
        )
    }
    
    func testRelativeNameCanNotEscape() throws {
        
        let relpath = "versions/../solution (copy).ipynb"
        
        let downloader = try TransferDownloader(topDirBasenames: ["versions", "hello"], progress: TransferOpMetrics(totalBytesCount: 100))

        XCTAssertThrowsError(
            try downloader.sanitizeRelativePath(relativePath: relpath)
        )
    }
    
    func testSanitizeRelativePathCanHandleParentUrls() throws {
        let relpathStandardized = "versions/solution (copy).ipynb"
        
        let relpath = "versions/../versions/solution (copy).ipynb"
        
        let downloader = try TransferDownloader(topDirBasenames: ["versions"], progress: TransferOpMetrics(totalBytesCount: 100))
        
        let result = try downloader.sanitizeRelativePath(relativePath: relpath)
        
        XCTAssertEqual(relpathStandardized, result.relativePath)
        
    }

    func testSanitizeRelativePathCanNotEscape2() throws {
        let relpath = "versions/../versions/../solution (copy).ipynb"
        
        let downloader = try TransferDownloader(topDirBasenames: ["versions"], progress: TransferOpMetrics(totalBytesCount: 100))
        
        XCTAssertThrowsError(
            try downloader.sanitizeRelativePath(relativePath: relpath)
        )
    }
    
}
