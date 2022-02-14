//
//  RemoteRegistration.swift
//  warpinator-project
//
//  Created by Emanuel on 12/02/2022.
//

import Foundation
import Sodium


class RemoteRegistration {
    
    let discovery: Discovery
    
    private let auth: Auth
    
    private var remotesDict: Dictionary<String, Remote>
    
    init(discovery: Discovery, auth: Auth) {
        self.discovery = discovery
        
        self.auth = auth
        
        self.remotesDict = .init()
        
        self.discovery.addOnRemoteChangedListener(self.onRemoteChangedListener)
    }
    
    func addPeer(mdnsPeer: MDNSPeer) async {
        if let oldRemote = self.remotesDict[mdnsPeer.name] {
            await oldRemote.update(with: mdnsPeer)
        } else {
            let newRemote = await Remote.from(mdnsPeer: mdnsPeer, actor: RemoteActor(auth: auth))
            
            await self.remotesDict[newRemote.name] = newRemote
            
            register(remote: newRemote)
        }
    }
    
    private func onRemoteChangedListener(change: Discovery.RemoteChanged) {
        Task {
            switch(change) {
            case .added(let peer):
                await self.addPeer(mdnsPeer: peer)
            case .removed(let name):
                await self.remotesDict[name]?.setActive(false)
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
    
    
    func register(remote: Remote) {
        /// First fetch certificate
        
        //        let cert = remote.mdnsPeer.resolveDNSName()
    }
}
