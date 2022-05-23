//
//  warpinator_projectApp.swift
//  Shared
//
//  Created by Emanuel on 09/02/2022.
//

import SwiftUI

@main
struct warpinator_projectApp: App {
    @Environment(\.scenePhase) var scenePhase
    
    var auth: Auth
    let warp: WarpBackend
    
    static func getIdentity(hostName: String) -> String {
        
        let key = "identity"
        
        if UserDefaults.standard.string(forKey: key) == nil {
            let newIdentity = Auth.computeIdentity(hostName: hostName)
            UserDefaults.standard.set(newIdentity, forKey: key)
        }
        
        return UserDefaults.standard.string(forKey: key)!
    }

    
    init() {
        let networkConfig = NetworkConfig()
        
        auth = Auth(networkConfig: networkConfig, identity: warpinator_projectApp.getIdentity(hostName: networkConfig.hostname))
        
        warp = WarpBackend.from(
            discoveryConfig: .init(identity: auth.identity, api_version: "2", auth_port: 42001, hostname: networkConfig.hostname),
            auth: auth
        )
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView(warp: warp)
        }.commands {
            SidebarCommands() // 1
        }
        #if os(macOS)
        .windowToolbarStyle(.unifiedCompact)
        #endif
        .onChange(of: scenePhase, perform: { phase in
            switch(phase) {
            case .background:
                return
            case .inactive:
                return
            case .active:
                warp.resetupListener()
            @unknown default:
                return
            }
        })
    }
}
