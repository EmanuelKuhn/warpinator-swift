//
//  Discovery.swift
//  warpinator-project
//
//  Created by Emanuel on 19/04/2022.
//

import Foundation

protocol PeerDiscovery {
    func addOnRemoteChangedListener(_ listener: @escaping RemoteChangeListener)
}

typealias RemoteChangeListener = (RemoteChanged) -> Void

enum RemoteChanged {
    case added(peer: Peer)
    case removed(name: String)
}
