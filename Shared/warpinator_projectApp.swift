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
    
    let warp: WarpBackend = .shared
    
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
                warp.pause()
                return
            case .inactive:
                warp.pause()
                return
            case .active:
                warp.resume()
                return
            @unknown default:
                return
            }
        })
        
        #if os(macOS)
        Settings {
            SettingsView()
        }
        #endif
    }
}
