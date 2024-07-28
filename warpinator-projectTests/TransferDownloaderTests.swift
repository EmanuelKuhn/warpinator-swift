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
        
        let downloader = try TransferDownloader(topDirBasenames: ["versions"], progress: TransferOpMetrics(totalBytesCount: 100), fileCount: 2)
        
        let result = try downloader.sanitizeRelativePath(relativePath: relpath)
        
        XCTAssertEqual(relpath, result.relativePath)
        
    }

    func testTopDirBasenamesCanHaveSpaces() throws {
        let downloader = try TransferDownloader(topDirBasenames: ["top dir name with spaces"], progress: TransferOpMetrics(totalBytesCount: 100), fileCount: 1)
        
        XCTAssertNotNil(downloader)
    }
    
    func testTopDirBasenamesCannotHaveMultipleComponents() throws {
        
        XCTAssertThrowsError(
            try TransferDownloader(topDirBasenames: ["nested/folder/"], progress: TransferOpMetrics(totalBytesCount: 100), fileCount: 2)
        )
    }

    func testTopDirBasenamesCannotHaveLinksToParentDir() throws {
        
        XCTAssertThrowsError(
            try TransferDownloader(topDirBasenames: [".."], progress: TransferOpMetrics(totalBytesCount: 100), fileCount: 1)
        )
    }

    func testTopDirBasenamesCannotBeEmpty() throws {
        
        XCTAssertThrowsError(
            try TransferDownloader(topDirBasenames: ["hey", ""], progress: TransferOpMetrics(totalBytesCount: 100), fileCount: 2)
        )
    }
    
    func testTopDirBasenamesCannotPointToRandomPath() throws {
        
        XCTAssertThrowsError(
            try TransferDownloader(topDirBasenames: ["/Users/throwaway/Downloads"], progress: TransferOpMetrics(totalBytesCount: 100), fileCount: 100)
        )
    }
    
    
    func testRelativeNameHasToStartWithTopDirName() throws {
        
        let relpath = "solution (copy).ipynb"
        
        let downloader = try TransferDownloader(topDirBasenames: ["versions", "hello"], progress: TransferOpMetrics(totalBytesCount: 100), fileCount: 3)

        XCTAssertThrowsError(
            try downloader.sanitizeRelativePath(relativePath: relpath)
        )
    }
    
    func testRelativeNameCanNotEscape() throws {
        
        let relpath = "versions/../solution (copy).ipynb"
        
        let downloader = try TransferDownloader(topDirBasenames: ["versions", "hello"], progress: TransferOpMetrics(totalBytesCount: 100), fileCount: 100)

        XCTAssertThrowsError(
            try downloader.sanitizeRelativePath(relativePath: relpath)
        )
    }
    
    func testSanitizeRelativePathCanHandleParentUrls() throws {
        let relpathStandardized = "versions/solution (copy).ipynb"
        
        let relpath = "versions/../versions/solution (copy).ipynb"
        
        let downloader = try TransferDownloader(topDirBasenames: ["versions"], progress: TransferOpMetrics(totalBytesCount: 100), fileCount: 100)
        
        let result = try downloader.sanitizeRelativePath(relativePath: relpath)
        
        XCTAssertEqual(relpathStandardized, result.relativePath)
        
    }

    func testSanitizeRelativePathCanNotEscape2() throws {
        let relpath = "versions/../versions/../solution (copy).ipynb"
        
        let downloader = try TransferDownloader(topDirBasenames: ["versions"], progress: TransferOpMetrics(totalBytesCount: 100), fileCount: 100)
        
        XCTAssertThrowsError(
            try downloader.sanitizeRelativePath(relativePath: relpath)
        )
    }
    
    
    func testSanitizeSymLink_validSymlink() throws {
        let relpath = "versions/link"
        let target = "target"
        
        let downloader = try TransferDownloader(topDirBasenames: ["versions"], progress: TransferOpMetrics(totalBytesCount: 100), fileCount: 100)

        let sanitizedTarget = try downloader.sanitizeSymLink(relativePath: relpath, targetPath: target)
        
        XCTAssertEqual(target, sanitizedTarget.path)
    }
    
    func testSanitizeSymLink_throwsPathTraversal() throws {
        let relpath = "version/link"
        let target = "../outside"  // attempts to navigate outside the 'versions' directory

        let downloader = try TransferDownloader(topDirBasenames: ["versions"], progress: TransferOpMetrics(totalBytesCount: 100), fileCount: 100)

        XCTAssertThrowsError(
            try downloader.sanitizeSymLink(relativePath: relpath, targetPath: target),
            "Should throw an error as it escapes the top directory"
        )
    }
    
    func testSanitizeSymLink_absolutePath() throws {
        let relpath = "versions/link"
        let target = "/etc/passwd"  // absolute path that should not be allowed

        let downloader = try TransferDownloader(topDirBasenames: ["versions"], progress: TransferOpMetrics(totalBytesCount: 100), fileCount: 100)

        XCTAssertThrowsError(
            try downloader.sanitizeSymLink(relativePath: relpath, targetPath: target),
            "Should throw an error as absolute paths should not be allowed"
        )
    }
    
    func testSanitizeSymLink_multipleTraversals() throws {
        let relpath = "versions/temp/link"
        let target = "../../versions/newtarget"  // resolves to versions/newtarget

        let downloader = try TransferDownloader(topDirBasenames: ["versions"], progress: TransferOpMetrics(totalBytesCount: 100), fileCount: 100)

        let sanitizedTarget = try downloader.sanitizeSymLink(relativePath: relpath, targetPath: target)

        XCTAssertEqual("../../versions/newtarget", sanitizedTarget.path)
    }
    
    func testSanitizeSymLink_pointsToDifferentTopDirBasename() throws {
        let relpath = "versions/link"
        let target = "../other/newtarget"  // resolves to versions/newtarget

        let downloader = try TransferDownloader(topDirBasenames: ["versions", "other"], progress: TransferOpMetrics(totalBytesCount: 100), fileCount: 100)

        let sanitizedTarget = try downloader.sanitizeSymLink(relativePath: relpath, targetPath: target)

        XCTAssertEqual("../other/newtarget", sanitizedTarget.path)
    }
    
    func testSanitizeSymLink_withSpaceInRelativePath() throws {
        let relpath = "version copy/link"
        let target = "target"  // resolves to versions/newtarget

        let downloader = try TransferDownloader(topDirBasenames: ["version copy"], progress: TransferOpMetrics(totalBytesCount: 100), fileCount: 100)

        let sanitizedTarget = try downloader.sanitizeSymLink(relativePath: relpath, targetPath: target)

        XCTAssertEqual("target", sanitizedTarget.path)
    }
    
    func testSanitizeSymLink_withSpaceInTarget() throws {
        let relpath = "version/link"
        let target = "target (copy)"  // resolves to versions/newtarget

        let downloader = try TransferDownloader(topDirBasenames: ["version"], progress: TransferOpMetrics(totalBytesCount: 100), fileCount: 100)

        let sanitizedTarget = try downloader.sanitizeSymLink(relativePath: relpath, targetPath: target)

        XCTAssertEqual("target (copy)", sanitizedTarget.path)
    }
}
