//
//  WarpBackend.swift
//  warpinator-project
//
//  Created by Emanuel on 12/02/2022.
//

import Foundation

class WarpBackend {
    
    let remoteRegistration: RemoteRegistration
        
    init(discovery: Discovery) {
        self.remoteRegistration = RemoteRegistration(discovery: discovery)
    }

    static func from(discoveryConfig: DiscoveryConfig) -> WarpBackend {
        return .init(discovery: .init(config: discoveryConfig))
    }
    
}
