//
//  RemoteRegistration.swift
//  warpinator-project
//
//  Created by Emanuel on 12/02/2022.
//

import Foundation
import Sodium
import NIOCore


actor RemoteRegistration {
    
    let discovery: PeerDiscovery
    
    private let auth: Auth
    
    private var remotesDict: Dictionary<String, Remote>
    
    private var remoteAddedCallbacks: Dictionary<UUID, (String)->Void> = .init()
    
    func addRemoteAddedCallback(uuid: UUID, callback: @escaping (String)->Void) {
        self.remoteAddedCallbacks[uuid] = callback
    }
    
    private func waitForRemoteAdded(remote id: String, timeout: TimeInterval) async {
        let callbackUUID = UUID()
        
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let timer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { _ in
                self.remoteAddedCallbacks.removeValue(forKey: callbackUUID)

                continuation.resume()
            }
            
            self.addRemoteAddedCallback(uuid: callbackUUID) { addedID in
                if addedID == id {
                    timer.invalidate()
                    self.remoteAddedCallbacks.removeValue(forKey: callbackUUID)

                    continuation.resume()
                }
            }
        }
    }
    
    subscript(id id: String, timeout timeout: TimeInterval = 5) -> Remote? {
        get async {

            if remotesDict.keys.contains(id) {
                return remotesDict[id]
            }
            
            await self.waitForRemoteAdded(remote: id, timeout: timeout)

            return remotesDict[id]
        }
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
        
        self.remoteAddedCallbacks.values.forEach {
            $0(peer.name)
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
        
        // Call listener with current values
        listener(Array(self.remotesDict.values))
    }
    
    private func onRemotesChanged() {
        self.onRemotesChangedListeners.forEach({
            $0(Array(self.remotesDict.values))
        })
    }
}
