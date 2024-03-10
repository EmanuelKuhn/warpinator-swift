//
//  warpinator_projectApp.swift
//  Shared
//
//  Created by Emanuel on 09/02/2022.
//

import SwiftUI

class WarpState: ObservableObject {
    
    var warp: WarpBackend
    
    init() {
        warp = WarpBackend()
    }
    
    func onScenePhaseChange(phase: ScenePhase) {
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
    }
}

@main
struct warpinator_projectApp: App {
    @Environment(\.scenePhase) var scenePhase
    
    let appState = WarpState()
    
    var body: some Scene {
        WindowGroup {
            ContentView(warp: appState.warp)
        }
        .onChange(of: scenePhase, perform: appState.onScenePhaseChange)



        .commands {
            SidebarCommands() // 1
        }
#if os(macOS)
        .windowToolbarStyle(.unifiedCompact)
#endif
        
#if os(macOS)
        Settings {
            SettingsView()
        }
#endif
    }
}
