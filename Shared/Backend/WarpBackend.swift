//
//  WarpBackend.swift
//  warpinator-project
//
//  Created by Emanuel on 12/02/2022.
//

import Foundation
import NIOCore
import GRPC

class WarpBackend {
    
    private let eventLoopGroup: EventLoopGroup
    
    private let auth: Auth
    private let discovery: BonjourDiscovery
    
    let remoteRegistration: RemoteRegistration
    
    init(discovery: BonjourDiscovery, auth: Auth) {
        self.eventLoopGroup = PlatformSupport.makeEventLoopGroup(loopCount: 2)
        
        self.discovery = discovery
        self.auth = auth
        
        self.remoteRegistration = RemoteRegistration(discovery: discovery, auth: auth, clientEventLoopGroup: eventLoopGroup)
    }

    static func from(discoveryConfig: DiscoveryConfig, auth: Auth) -> WarpBackend {
        return .init(discovery: .init(config: discoveryConfig), auth: auth)
    }
    
    func start() {
        
        // Start servers
        let certServer = CertServerV2(auth: auth)
        
        DispatchQueue.global(qos: .userInitiated).async {
            try? certServer.run(eventLoopGroup: self.eventLoopGroup)
        }
        
        let warpServer = WarpServer(auth: auth, remoteRegistration: self.remoteRegistration)
        
        DispatchQueue.global(qos: .userInitiated).async {
            try? warpServer.run(eventLoopGroup: self.eventLoopGroup)
        }
        
        // Start bonjour discovery
        DispatchQueue.global(qos: .userInitiated).async {
            self.discovery.setupListener()
            
            print("setup listener done")
            
            self.discovery.setupBrowser()
            
            print("setup browser")
        }
    }
    
    func resetupListener() {
        // Start bonjour discovery
        DispatchQueue.global(qos: .userInitiated).async {
            self.discovery.setupListener()
            
            print("setup listener done")
        }
    }
    
}
