//
//  RemoteRegistration.swift
//  warpinator-project
//
//  Created by Emanuel on 12/02/2022.
//

import Foundation


class RemoteRegistration {
    
    struct Remote {
        let id: String
        
        let mdnsPeer: MDNSPeer
        
        var certificate: String? = nil
        
        static func from(mdnsPeer: MDNSPeer) -> Remote {
            return .init(id: mdnsPeer.computeKey(), mdnsPeer: mdnsPeer)
        }
        
        func update(with mdnsPeer: MDNSPeer) {
            assert(mdnsPeer.computeKey() == self.id)
            
            
            print("TODO: update with peer")
        }
    }
    
    let discovery: Discovery
    
    private var remotesDict: Dictionary<String, Remote>
    
    init(discovery: Discovery) {
        self.discovery = discovery
        
        self.remotesDict = .init()
    }
    
    func addPeer(mdnsPeer: MDNSPeer) {
        if let oldRemote = self.remotesDict[mdnsPeer.computeKey()] {
            oldRemote.update(with: mdnsPeer)
        } else {
            let newRemote = Remote.from(mdnsPeer: mdnsPeer)
            
            self.remotesDict[newRemote.id] = newRemote
            
            register(remote: newRemote)
        }
        
        
    }
    
    func register(remote: Remote) {
        /// First fetch certificate
        
        //        let cert = getCerremote: RemoteRegistration.Remote()
    }
}
