//
//  warpinator_projectApp.swift
//  Shared
//
//  Created by Emanuel on 09/02/2022.
//

import SwiftUI

@main
struct warpinator_projectApp: App {
    
    var auth: Auth
    let warp: WarpBackend
    
    init() {
        let networkConfig = NetworkConfig()
        
        auth = Auth(networkConfig: networkConfig)
        
        warp = WarpBackend.from(
            discoveryConfig: .init(identity: auth.identity, api_version: "2", auth_port: 42001, hostname: networkConfig.hostname),
            auth: auth
        )
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView(warp: warp)
        }
    }
}
