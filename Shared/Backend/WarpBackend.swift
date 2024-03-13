//
//  WarpBackend.swift
//  warpinator-project
//
//  Created by Emanuel on 12/02/2022.
//

import Foundation
import NIOCore
import GRPC

enum WarpState {
    case starting, stopped, running, failure(_ error: WarpError), restarting
}

enum WarpError: Error {
    case failedToStart(Error), failedToStop(Error), failedToDiscoverSelf
}

extension WarpError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .failedToStart(let error):
            return NSLocalizedString("Failed to start server: \(error)", comment: "Failed to start")
        case .failedToStop(let error):
            return NSLocalizedString("Failed to stop server: \(error)", comment: "Failed to stop server")
        case .failedToDiscoverSelf:
            return NSLocalizedString("Unable to discover self. Please check if app has local network permission", comment: "Failed to stop server")
        }
    }
}

protocol WarpObserverDelegate: AnyObject {
    func stateDidUpdate(newState: WarpState)
}

class WarpBackend {
    private let settings: WarpSettings
    
    private let eventLoopGroup: EventLoopGroup
    
    private let auth: Auth
    private let discovery: BonjourDiscovery
    
    let remoteRegistration: RemoteRegistration
    
    var isStarted = false
    
    var isFirstStart = true
    
    private var certServer: CertServerV2? = nil
    private var warpServer: WarpServer? = nil
    
    weak var delegate: WarpObserverDelegate?
    
    var state: WarpState = .stopped
    
    init(delegate: WarpObserverDelegate?=nil) {
        
        self.delegate = delegate
        
        self.settings = WarpSetingsUserDefaults.shared
        self.eventLoopGroup = PlatformSupport.makeEventLoopGroup(loopCount: 2)

        let networkConfig = NetworkConfig.shared
        
        self.auth = Auth(networkConfig: networkConfig, identity: settings.identity, groupCode: settings.groupCode)
        
        let discoveryConfig = DiscoveryConfig(identity: auth.identity, api_version: "2", auth_port: settings.authPort, hostname: networkConfig.hostname)

        self.discovery = BonjourDiscovery(config: discoveryConfig)
        
        self.remoteRegistration = RemoteRegistration(discovery: discovery, auth: auth, clientEventLoopGroup: eventLoopGroup)

        // Add callback for when connection settings change
        settings.addOnConnectionSettingsChangedCallback(onConnectionSettingsChanged)
    }
    
    func updateState(newState: WarpState) {
        self.state = newState
        
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.stateDidUpdate(newState: newState)
        }
    }
    
    func onConnectionSettingsChanged() {
        
        // This operation will trigger a restart
        self.updateState(newState: .restarting)
        
        // Set groupcode to potentially new value
        auth.groupCode = settings.groupCode
        
        // Generate new server certificate when changing connection settings
        auth.regenerateCertificate()
        
        restart()
    }
    
    func start() {
                
        if isStarted {
            return
        }
        
        self.updateState(newState: .starting)
        
        isStarted = true
        
        // Start servers
        let certServer = CertServerV2(auth: auth, auth_port: settings.authPort)
        self.certServer = certServer
        
        DispatchQueue.global(qos: .userInitiated).async {
            try? certServer.run(eventLoopGroup: self.eventLoopGroup)
        }
                
        let warpServer = WarpServer(auth: auth, remoteRegistration: self.remoteRegistration, port: settings.port)
        self.warpServer = warpServer
        
        DispatchQueue.global(qos: .userInitiated).async {
            try? warpServer.run(eventLoopGroup: self.eventLoopGroup, completion: { result in
                switch result {
                case .success():
                    print("WarpServer started succesfully")
                case .failure(let error):
                    print("WarpServer failed to start: \(error)")
                    
                    self.updateState(newState: .failure(.failedToStart(error)))
                }
            })
        }
        
        // Start bonjour discovery
        DispatchQueue.global(qos: .userInitiated).async {
            self.discovery.setupBrowser()
            
            print("setup browser")

            
            self.discovery.setupListener(port: UInt16(self.settings.port))
            
            print("setup listener done")
            
            self.isFirstStart = false
            
            self.updateState(newState: .running)
            
            // After some seconds, poll if app was able to find any remote
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                if !self.discovery.hasReachedLocalNetwork {
                    self.updateState(newState: .failure(.failedToDiscoverSelf))
                }
            }
        }
    }
    
    func pause() {
        self.discovery.pauseBonjour()
    }
    
    func resume() {
        self.discovery.refreshService()
        
        self.discovery.setupBrowser()
    }
    
    func resetupListener() {
        
        // Start bonjour discovery
        DispatchQueue.global(qos: .userInitiated).async {
            
            self.pause()
            
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                self.resume()
            }
        }
    }
    
    func stop() {
        if !isStarted {
            return
        }
        
        self.updateState(newState: .stopped)
        
        isStarted = false
        
        // Perform all operations on a background queue
        DispatchQueue.global(qos: .userInitiated).async {
            self.discovery.pauseBonjour()

            // Close the current server
            do {
                try self.warpServer?.close()
                self.warpServer = nil
                
                try self.certServer?.close()
                self.certServer = nil
            } catch {
                print("Restarting: Error closing warpServer: \(error)")

                self.updateState(newState: .failure(.failedToStop(error)))
                
                return
            }
        }
    }

    
    func restart() {
        
        if isFirstStart {
            return start()
        }
        
        self.stop()
            
        print("Restarting: Stopped server; waiting 5 seconds")
        
        // Need to wait some time for network port to be released
        // 1 second was too little, 5 works most of the time
        Thread.sleep(forTimeInterval: 5.0)

        print("Restarting: Finished waiting")
                
        self.start()
    }
    
}
