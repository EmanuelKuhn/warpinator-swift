//
//  TestDiscovery.swift
//  warpinator-projectTests
//
//  Created by Emanuel on 23/04/2022.
//

import Foundation

@testable import warpinator_project

/// A mock `Peer` implementation with fixed resolve() values.
struct TestPeer: Peer {
    
    var name: String
    
    var hostName: String
    
    var fetchCertInfo: FetchCertInfo?
    
    let resolveResult: (String, Int)
    
    func resolve() async throws -> (String, Int) {
        return resolveResult
    }
    
    init(name: String, hostName: String, authPort: Int, resolveResult: (String, Int)) {
        self.name = name
        self.hostName = hostName
        
        self.fetchCertInfo = .authPort(authPort)
        self.resolveResult = resolveResult
    }
    
    
}

/// A mock `PeerDiscovery` that will send RemoteChanged messages whenever `callListeners(change)` is called.
class TestDiscovery: PeerDiscovery {
    
    var listeners: [RemoteChangeListener] = []
    
    func addOnRemoteChangedListener(_ listener: @escaping RemoteChangeListener) {
        listeners.append(listener)
    }
    
    func callListeners(change: RemoteChanged) {
        listeners.forEach {
            $0(change)
        }
    }
}
