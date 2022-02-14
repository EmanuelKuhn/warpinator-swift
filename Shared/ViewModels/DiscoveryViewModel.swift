//
//  DiscoveryViewModel.swift
//  warpinator-project
//
//  Created by Emanuel on 12/02/2022.
//

import Foundation


class DiscoveryViewModel: ObservableObject {

    struct VMRemote: Identifiable {
        let id: String
        let title: String
        
        let peer: MDNSPeer
        
        fileprivate let remote: Remote
        
        func ping() async {
            
            await remote.requestCertificate()
            
            print("ping: \(try? await remote.ping(remote: remote))")
        }
    }
    
    @Published var remotes: Array<VMRemote> = []
    
    init(warp: WarpBackend) {
        warp.remoteRegistration.addOnRemoteChangedListener { remotes in
            print("DiscoveryViewModel: onRemotesChangedListener")
            
            self.remotes = remotes.map({ remote in
                VMRemote(id: remote.name, title: "\(remote.mdnsPeer.txtRecord["hostname"] ?? ""): \(remote.name)", peer: remote.mdnsPeer, remote: remote)
            })
        }
    }
    
}
