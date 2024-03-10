//
//  warpinator_projectApp.swift
//  Shared
//
//  Created by Emanuel on 09/02/2022.
//

import SwiftUI



class AppState: ObservableObject, WarpObserverDelegate {
    
    @Published
    var state: WarpState = .stopped
    
    private var warp: WarpBackend
    
    var remoteRegistration: RemoteRegistrationObserver {
        warp.remoteRegistration
    }
    
    init() {
        warp = WarpBackend()
        
        warp.delegate = self
        
        self.state = warp.state
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
    
    func stateDidUpdate(newState: WarpState) {
        precondition(Thread.isMainThread)
        
        state = newState
        
        print("AppState: state = \(newState)")

    }
    
    func start() {
        DispatchQueue.global().async {
            self.warp.start()
        }
    }
    
    func stop() {
        DispatchQueue.global().async {
            self.warp.stop()
        }
    }

    func restart() {
        DispatchQueue.global().async {
            self.warp.restart()
        }
    }
    
    func resetupListener() {
        warp.resetupListener()
    }

}

@main
struct warpinator_projectApp: App {
    @Environment(\.scenePhase) var scenePhase
    
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
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
