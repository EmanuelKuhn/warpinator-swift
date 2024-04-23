//
//  TransferOpStateTests.swift
//  warpinator-projectTests
//
//  Created by Emanuel on 23/04/2024.
//

import Foundation

import XCTest
@testable import warpinator_project

class TransferOpTests: XCTestCase {
    var transferOpFromRemote: TransferOp!
    
    var peer: Peer!
    var remote: Remote!

    override func setUp() {
        super.setUp()
        
        peer = TestPeer(name: "some-peer-name", hostName: "peer.local", resolveResult: ("0.1.2.3", 42000))
                
        let remote = MockRemote(peer: peer)
        
        transferOpFromRemote = TransferFromRemote(timestamp: 12345,
                                        title: "warpinator-project.app.dSYM.zip",
                                        mimeType: "archive/zip",
                                        size: 1430000,
                                        count: 1,
                                        topDirBasenames: ["warpinator-project.app.dSYM.zip"],
                                        initialState: .requested,
                                        remote: remote
        )
    }

    override func tearDown() {
        transferOpFromRemote = nil
        super.tearDown()
    }
        
    func testValidTransitionToStarted() {
        transferOpFromRemote.tryEvent(event: .start)
        XCTAssertEqual(transferOpFromRemote.state, .started, "The state should transition to started from requested")
    }
    
    func testCancellationFromRequestedState() {
        // Should be ignored
        transferOpFromRemote.tryEvent(event: .requested)
        transferOpFromRemote.tryEvent(event: .cancelledByUser)
        XCTAssertEqual(transferOpFromRemote.state, .requestCanceled, "The state should transition to requestCanceled from requested")
    }
    
    func testTransitionToFailureWithErrorMessage() {
        transferOpFromRemote.tryEvent(event: .start)
        
        let failureReason = "Network Error"
        
        transferOpFromRemote.tryEvent(event: .failure(reason: failureReason))
        
        transferOpFromRemote.tryEvent(event: .completed)
        
        XCTAssertNotEqual(transferOpFromRemote.state, .completed, "The state should not transition to completed after a failure")
        
        guard case .failed(let reason) = transferOpFromRemote.state else {
            return XCTFail("State should be .failed")
        }
        
        XCTAssertEqual(reason, failureReason, "The state should include the failure reason")
    }
    
    func testNoTransitionForInvalidEvent() {
        let initialState = transferOpFromRemote.state
        transferOpFromRemote.tryEvent(event: .completed)
                
        XCTAssertEqual(transferOpFromRemote.state, initialState, "The state should not change on an invalid event")
    }
    
    func testStateShouldStayCancelledAfterFailure() {
        transferOpFromRemote.tryEvent(event: .requested)
        transferOpFromRemote.tryEvent(event: .requestCancelledByRemote)
        transferOpFromRemote.tryEvent(event: .failure(reason: "some failure"))
                
        XCTAssertEqual(transferOpFromRemote.state, .requestCanceled, "The state should stay on cancelled")
    }
    
    func testCanCancelAfterCompletion() {
        // This is the expected behaviour, because one of the remotes might cancel just before completing the transfer, and then the other one should also cancel.
        
        transferOpFromRemote.tryEvent(event: .start)
        transferOpFromRemote.tryEvent(event: .completed)

        transferOpFromRemote.tryEvent(event: .transferCancelledByRemote)
        
        XCTAssertEqual(transferOpFromRemote.state, .transferCanceled, "The state should become canceled even when canceling after completing")
    }
    
    func testShouldNotCompleteAfterCancelled() {
        transferOpFromRemote.tryEvent(event: .start)
        transferOpFromRemote.tryEvent(event: .transferCancelledByRemote)

        transferOpFromRemote.tryEvent(event: .completed)
        
        XCTAssertEqual(transferOpFromRemote.state, .transferCanceled, "The state should not become complete after cancellation")
    }

    
    func testStateShouldReflectLastFailure() {
        transferOpFromRemote.tryEvent(event: .start)
        transferOpFromRemote.tryEvent(event: .failure(reason: "some failure"))
        
        transferOpFromRemote.tryEvent(event: .failure(reason: "some other failure"))

        XCTAssertEqual(transferOpFromRemote.state, .failed(reason: "some other failure"), "The state should reflect the last failure")
    }
}
