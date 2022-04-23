//
//  Peer.swift
//  warpinator-project
//
//  Created by Emanuel on 19/04/2022.
//

import Foundation

protocol Peer {
    
    var name: String { get }
    var hostName: String { get }
    
    var fetchCertInfo: FetchCertInfo? { get }
    
    /// Resolve the host, port of the peer to connect to it.
    func resolve() async throws -> (String, Int)
}

enum FetchCertInfo {
    case authPort(_ port: Int)
}
