//
//  WarpManager.swift
//  warpinator-project
//
//  Created by Emanuel on 14/03/2024.
//

import Foundation

#if canImport(UIKit)
import UIKit
#endif

import os

enum WarpState {
    case unableToDiscoverSelf
    
    case notInitialized
    case running
    case failure(_ error: WarpError)
    case restarting
}

enum WarpError: Error {
    case failedToStart(Error)
}

extension WarpError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .failedToStart(let error):
            return NSLocalizedString("Failed to start server: \(error)", comment: "Failed to start")
        }
    }
}

protocol WarpObserverDelegate: AnyObject {
    func stateDidUpdate(newState: WarpState)
    
    // Delegate is called by WarpManager after starting to pass the RemoteRegistrationObserver object to the delegate.
    func warpStarted(remoteRegistration: RemoteRegistrationObserver)
}


actor WarpManager {
    
    enum ManagerState {
        case idle
        case starting
        case running
        case restarting
        case suspended
    }
   
    // State that is used to track the lifecycle of the Warp instance
    private var managerState: ManagerState = .idle
    
    private let settings: WarpSettings = WarpSetingsUserDefaults.shared
    
#if canImport(UIKit)
    private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid
#endif
    
    // State that is shown in the UI, and reflects internal errors
    var warpState: WarpState = .notInitialized {
        didSet {
            let warpState = self.warpState
            
            print("WarpManager warpState didset: \(managerState)")
            
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
        guard managerState == .idle || managerState == .restarting else {
            return
        }
        
        managerState = .starting
        
        if self.warp == nil {
            await self.initialize()
        }
        
        guard let warp = warp else {
            preconditionFailure()
        }
        
        do {
            try await warp.start()
            
            await startBackgroundTask()
        } catch {
            self.warpState = .failure(.failedToStart(error))
            self.managerState = .idle
            
            return
        }
        
        if let delegate = delegate {
            await MainActor.run {
                delegate.warpStarted(remoteRegistration: warp.remoteRegistration)
            }
        }
        
        self.warpState = .running
        self.managerState = .running
    }
    
    func resetupListener() {
        self.warp?.resetupListener()
    }
    
    func background() {
        // Don't need to handle this, as using the startBackgroundTask experiation handler
    }
    
    func shouldSuspend() {
        
        os_log("Called WarpManager.shouldSuspend()")
        
        managerState = .suspended
        
        self.endBackgroundTask()
    }
    
    func pause() {
        self.warp?.pause()
    }
    
    func resume() async {
        if managerState == .running {
            // Just refresh bonjour
            self.warp?.resume()
        } else {
            // e.g. when backgrounded, or for some other reason wasn't running
            await restart()
        }
    }
    
    func setDelegate(delegate: WarpObserverDelegate) {
        self.delegate = delegate
    }
    
    func onConnectionSettingsChanged() async {
        await restart()
    }
    
    func restart() async {
        
        guard managerState != .restarting else { return }
        managerState = .restarting
        
        // This operation will trigger a restart
        warpState = .restarting

        self.warp?.stop()
        
        self.warp = nil
        
        warpState = .notInitialized
        
        // Needed for iOS
        endBackgroundTask()
        
        do {
            try await Task.sleep(nanoseconds: 1_000_000_000)
        } catch {
            // Don't call start on cancellation
            return
        }
        
        guard managerState == .restarting else {
            // The state was modified outside of restart()
            // This can happen because actors still suspend and allow other methods to run at await suspension points (.i.e. Task.sleep)
            return
        }
        
        await start()
    }
    
    private func startBackgroundTask() async {
#if canImport(UIKit)
        self.backgroundTaskId = await UIApplication.shared.beginBackgroundTask(withName: "WarpManager.start", expirationHandler: { [weak self] in
            
            let ref = self
            
            _ = Task.detached {
                await ref?.shouldSuspend()
            }
            
        })
#endif
    }
    
    private func endBackgroundTask() {
#if canImport(UIKit)
        let backgroundTaskId = self.backgroundTaskId
        
        if backgroundTaskId != .invalid {
            Task.detached {
                await UIApplication.shared.endBackgroundTask(backgroundTaskId)
            }
        }
        self.backgroundTaskId = .invalid
#endif
    }
}
