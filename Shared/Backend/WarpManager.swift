//
//  WarpManager.swift
//  warpinator-project
//
//  Created by Emanuel on 14/03/2024.
//

import Foundation

enum WarpState: Equatable {
    case unableToDiscoverSelf
    
    case notInitialized
    case starting
    case running
    case stopped
    case failure(_ error: WarpError)
    case restarting
}

enum WarpError: Error, Equatable {
    case failedToStart(Error), failedToStop(Error) //, failedToDiscoverSelf
    
    static func == (lhs: WarpError, rhs: WarpError) -> Bool {
        switch (lhs, rhs) {
        case (.failedToStart, .failedToStart),
            (.failedToStop, .failedToStop):
//             (.failedToDiscoverSelf, .failedToDiscoverSelf):
            return true
        default:
            return false
        }
    }
}

extension WarpError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .failedToStart(let error):
            return NSLocalizedString("Failed to start server: \(error)", comment: "Failed to start")
        case .failedToStop(let error):
            return NSLocalizedString("Failed to stop server: \(error)", comment: "Failed to stop server")
//        case .failedToDiscoverSelf:
//            return NSLocalizedString("Unable to discover self. Please check if app has local network permission", comment: "Failed to stop server")
        }
    }
}

extension String: Error {
    
}

protocol WarpObserverDelegate: AnyObject {
    func stateDidUpdate(newState: WarpState)
    
    func warpStarted(remoteRegistration: RemoteRegistration)
}


actor WarpManager {
    
    enum ManagerState {
        case idle
        case starting
        case running
        case stopping
        case restartingForSettings
    }
    
    private var state: ManagerState = .idle
    
    private let settings: WarpSettings = WarpSetingsUserDefaults.shared
    
    var warpState: WarpState = .notInitialized {
        didSet {
            let warpState = self.warpState

            print("WarpManager state didset: \(state)")

            guard let delegate = self.delegate else { return }
   
            Task {
                await MainActor.run {
                    delegate.stateDidUpdate(newState: warpState)
                }
            }
        }
    }

    var warp: WarpBackend? =  nil
    
    var delegate: WarpObserverDelegate?
    
    private func waitForLocalNetworkPermission() async {
        var granted = false

        var timeout = 2.0

        while !granted {
            granted = await requestLocalNetworkPermissionAsync(timeout: timeout)

            if !granted {
                warpState = .unableToDiscoverSelf
            }

            timeout = 5.0
        }
    }
    
    private func initialize() async {
        // Not needed on macOS:
        #if !os(macOS)
        await self.waitForLocalNetworkPermission()
        #endif
        
        self.warp = WarpBackend()
        
        self.settings.addOnConnectionSettingsChangedCallback {
            Task.detached {
                await self.onConnectionSettingsChanged()
            }
        }

    }
    
    func start() async {
        guard state == .idle else {
            return
        }
        
        state = .starting
        
        if self.warp == nil {
            await self.initialize()
        }
        
        guard let warp = warp else {
            preconditionFailure()
        }
        
        do {
            try await warp.start()
        } catch {
            self.warpState = .failure(.failedToStart(error))
            self.state = .idle
            
            return
        }
        
        if let delegate = delegate {
            await MainActor.run {
                delegate.warpStarted(remoteRegistration: warp.remoteRegistration)
            }
        }
        
        self.warpState = .running
        self.state = .running
    }

    func stop() async {
        
        guard state == .running || state == .restartingForSettings else { return }

        
        do {
            try await self.warp?.stop()
            warpState = .stopped
        } catch {
            warpState = .failure(.failedToStop(error))
        }
     
        state = .idle
    }

    func restart() async {
        print("restart called")
        guard warp != nil else {
            return await start()
        }
        
        if state == .idle {
            return await start()
        }
        print("going through with restart")

        await stop()
         
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        
        await start()
    }
    
    func resetupListener() {
        self.warp?.resetupListener()
    }
    
    func pause() {
        self.warp?.pause()
    }

    func resume() {
        self.warp?.resume()
    }
    
    func setDelegate(delegate: WarpObserverDelegate) {
        self.delegate = delegate
    }
    
    func onConnectionSettingsChanged() async {
        
        guard state != .restartingForSettings else { return }
        
        state = .restartingForSettings
        
        guard let warp = warp else { return }
        
        // This operation will trigger a restart
        self.warpState = .restarting

        // Set groupcode to potentially new value
        warp.regenerateCertificate()

        await restart()
    }

}
