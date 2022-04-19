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
        
        func onTapFunc(urls: [URL]) async {
            print("ontap \(self.title)")
            
            try? await self.remote.requestTransfer(urls: urls)
        }
    }
    
    @Published var remotes: Array<VMRemote> = []
    
    init(warp: WarpBackend) {
        warp.remoteRegistration.addOnRemoteChangedListener { remotes in
            print("DiscoveryViewModel: onRemotesChangedListener")
            
            Task {
                self.setRemotes(remotes: remotes.map({ remote in
                    VMRemote(id: remote.id, title: "\(remote.mdnsPeer.txtRecord["hostname"] ?? ""): \(remote.id)", peer: remote.mdnsPeer, remote: remote)
                }))
            }
        }
    }
    
    func setRemotes(remotes: Array<VMRemote>) {
        DispatchQueue.main.async {
            self.remotes = remotes
        }
        
    }
    
}
