//
//  warpinator_projectApp.swift
//  Shared
//
//  Created by Emanuel on 09/02/2022.
//

import SwiftUI


import Network


//// Queue used to serialize calls to warp.start(), warp.restart(), warp.pause()...
//let serialWarpActionQueue = DispatchQueue.init(label: "io.github.emanuelkuhn.warpinator-swift.warp-action-queue")

class AppState: ObservableObject, WarpObserverDelegate {
    
    func warpStarted(remoteRegistration: RemoteRegistration) {
        precondition(Thread.isMainThread)

        self.remoteRegistration = remoteRegistration
        
//        Task.detached {
//            await self.remoteRegistration.addOnRemoteChangedListener { remotes in
//                remotes.first?.id
//            }
//        }
    }
    
    
    @Published
    var state: WarpState = .notInitialized
    
    var remoteRegistration: RemoteRegistration! = nil

    var hasNetworkPermission = false
    
    var warpManager: WarpManager
    
    init() {
        self.warpManager = WarpManager()
        
        Task.detached { [self] in
            await warpManager.setDelegate(delegate: self)
        }
    }

    func onScenePhaseChange(phase: ScenePhase) {
        switch(phase) {
        case .background:
            Task.detached {
                await self.warpManager.pause()
            }
            return
        case .inactive:
            Task.detached {
                await self.warpManager.pause()
            }
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
    
//    func start() async {
//        await self.warpManager.start()
//    }
        

    
}

@main
struct warpinator_projectApp: App {
    @Environment(\.scenePhase) var scenePhase
    
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
//            if appState.initialized {
                ContentView()
                    .environmentObject(appState)
                    .onAppear {
                        print("Calling start")
                        
                        Task.detached {
                            await appState.warpManager.start()
                        }
                    }
                
//            } else {
//                ProgressView("Waiting for network permission.")
//                    .onAppear {
//                        print("Calling start")
//                        appState.start()
//                    }
//                Button("Try again") {
//                    appState.start()
//                }
//            }
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
