//
//  WarpBackend.swift
//  warpinator-project
//
//  Created by Emanuel on 12/02/2022.
//

import Foundation

class WarpBackend {
    
    let remoteRegistration: RemoteRegistration
        
    init(discovery: Discovery, auth: Auth) {
        self.remoteRegistration = RemoteRegistration(discovery: discovery, auth: auth)
    }

    static func from(discoveryConfig: DiscoveryConfig, auth: Auth) -> WarpBackend {
        return .init(discovery: .init(config: discoveryConfig), auth: auth)
    }
    
}
