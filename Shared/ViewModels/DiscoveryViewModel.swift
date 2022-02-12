//
//  DiscoveryViewModel.swift
//  warpinator-project
//
//  Created by Emanuel on 12/02/2022.
//

import Foundation

struct Remote: Identifiable {
    let id: String
    let title: String
    
    let peer: MDNSPeer
}

class DiscoveryViewModel: ObservableObject {
    
    @Published var remotes: Array<Remote> = []
    
    init(warp: WarpBackend) {
        warp.remoteRegistration.discovery.addOnRemotesChangedListener {
            
            print("DiscoveryViewModel: onRemotesChangedListener")
            
            self.remotes = warp.remoteRegistration.discovery.remotes.map({ peer in
                Remote(id: peer.computeKey(), title: "\(peer.txtRecord["hostname"] ?? ""): \(peer.name)", peer: peer)
            })
        }
    }
    
}
