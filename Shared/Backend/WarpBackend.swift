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
    
    let eventLoopGroup: EventLoopGroup
    
    let auth: Auth
    let discovery: BonjourDiscovery
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
    
}
