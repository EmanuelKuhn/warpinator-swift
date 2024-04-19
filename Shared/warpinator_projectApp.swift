//
//  warpinator_projectApp.swift
//  Shared
//
//  Created by Emanuel on 09/02/2022.
//

import SwiftUI



class AppState: ObservableObject, WarpObserverDelegate {
    
    @Published
    var state: WarpState = .notInitialized
    
    // Needed for the DiscoveryViewModel (the view that shows discovered devices)
    var remoteRegistration: RemoteRegistrationObserver! = nil

    var hasNetworkPermission = false
    
    
    var warpManager: WarpManager
    
    init() {
        self.warpManager = WarpManager()
        
        Task.detached { [self] in
            await warpManager.setDelegate(delegate: self)
        }
    }
    
    func warpStarted(remoteRegistration: RemoteRegistrationObserver) {
        precondition(Thread.isMainThread)

        self.remoteRegistration = remoteRegistration
    }
    
    func onScenePhaseChange(phase: ScenePhase) {
        switch(phase) {
        case .background:
//            Task.detached {
//                await self.warpManager.background()
//            }
            return
        case .inactive:
//            Task.detached {
//                await self.warpManager.pause()
//            }
            return
        case .active:
            Task.detached {
                await self.warpManager.resume()
            }
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
}

@main
struct warpinator_projectApp: App {
    @Environment(\.scenePhase) var scenePhase
    
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .onAppear {
                    print("Calling start")
                    
                    Task.detached {
                        await appState.warpManager.start()
                    }
                }
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
