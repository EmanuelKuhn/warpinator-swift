//
//  WarpProviderTests.swift
//  Tests iOS
//
//  Created by Emanuel on 18/04/2022.
//

import XCTest
@testable import warpinator_project

import GRPC
import NIO



//extension Remote {
//    static func fromTestPeer(peer: TestPeer, auth: Auth, eventLoopGroup: EventLoopGroup) async -> Remote {
//        return await Remote(id: peer.name, peer: peer, auth: auth, eventLoopGroup: eventLoopGroup)
//    }
//}


final class WarpIntegrationTests: XCTestCase {
    
    var instances: [TestWarpInstance] = []
    
    func setupWarpInstance(_ identity: String, port: Int, authPort: Int, flag: Bool=false) async -> TestWarpInstance {
        let done_warpenv = self.expectation(description: "setupWarpInstance(\(port), \(authPort)")
        
        let warpEnv = TestWarpInstance(identity: identity, port: port, authPort: authPort)
        await warpEnv.run { result in
            do {
                try result.get()
            } catch {
                assertionFailure("failed to start warp instance: \(error)")
            }
            
            done_warpenv.fulfill()
        }
        
        await waitForExpectations(timeout: 5, handler: nil)
        
        instances.append(warpEnv)
        
        return warpEnv
    }
    
    override func tearDown() {
        
        XCTAssertNoThrow(try instances.forEach {
            XCTAssertNoThrow(try $0.close())
        })
        
        instances = []
        
        super.tearDown()
    }
    
    private var nextPort = 43000
    
    func getPort() -> Int {
        return Int.random(in: 12000...60000)
    }
    
    func testPing() async throws {
        // Given
        
        let otherWarp = await setupWarpInstance("otherWarp", port: getPort(), authPort: getPort())
        
        let sot = await setupWarpInstance("sot", port: getPort(), authPort: getPort())
        let client = try await sot.connect()
        
        // When
//
        let result = try await client.ping(otherWarp.lookupName, callOptions: nil)
//
//        // Assert
//
        XCTAssertEqual(result, VoidType())
    }
    
}
