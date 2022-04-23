//
//  RemoteRegistration.swift
//  warpinator-project
//
//  Created by Emanuel on 12/02/2022.
//

import Foundation
import Sodium
import NIOCore


class RemoteRegistration {
    
    let discovery: PeerDiscovery
    
    private let auth: Auth
    
    private var remotesDict: Dictionary<String, Remote>
    
    subscript(id id: String) -> Remote? {
        get { return remotesDict[id] }
    }
    
    var keys: Array<String> {
        Array(remotesDict.keys)
    }

    let eventLoopGroup: EventLoopGroup
    
    init(discovery: PeerDiscovery, auth: Auth, clientEventLoopGroup: EventLoopGroup) {
        self.discovery = discovery
        
        self.auth = auth
        
        self.eventLoopGroup = clientEventLoopGroup
        
        self.remotesDict = .init()
        
        self.discovery.addOnRemoteChangedListener(self.onRemoteChangedListener)
    }
    
    func addPeer(peer: Peer) async {
        if let oldRemote = self.remotesDict[peer.name] {
            oldRemote.update(with: peer)
        } else {
            let newRemote = await Remote.from(peer: peer, auth: auth, eventLoopGroup: self.eventLoopGroup)
            
            self.remotesDict[newRemote.id] = newRemote
        }
    }
    
    private func onRemoteChangedListener(change: RemoteChanged) {
        Task {
            switch(change) {
            case .added(let peer):
                await self.addPeer(peer: peer)
            case .removed(let name):
                self.remotesDict[name]?.setActive(false)
            }
            
            // Send update
            onRemotesChanged()
        }
    }
    
    private var onRemotesChangedListeners: Array<(Array<Remote>) -> Void> = []
    
    func addOnRemoteChangedListener(_ listener: @escaping (Array<Remote>) -> Void) {
        self.onRemotesChangedListeners.append(listener)
    }
    
    private func onRemotesChanged() {
        self.onRemotesChangedListeners.forEach({
            $0(Array(self.remotesDict.values))
        })
    }
}
