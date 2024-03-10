//
//  WarpBackend.swift
//  warpinator-project
//
//  Created by Emanuel on 12/02/2022.
//

import Foundation
import NIOCore
import GRPC

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
    
    init() {
        
        self.settings = WarpSetingsUserDefaults.shared
        self.eventLoopGroup = PlatformSupport.makeEventLoopGroup(loopCount: 2)

        let networkConfig = NetworkConfig.shared
        
        self.auth = Auth(networkConfig: networkConfig, identity: settings.identity, groupCode: settings.groupCode)
        
        let discoveryConfig = DiscoveryConfig(identity: auth.identity, api_version: "2", auth_port: settings.authPort, hostname: networkConfig.hostname)

        self.discovery = BonjourDiscovery(config: discoveryConfig)
        
        self.remoteRegistration = RemoteRegistration(discovery: discovery, auth: auth, clientEventLoopGroup: eventLoopGroup)

//         Add callback for when connection settings change
        settings.addOnConnectionSettingsChangedCallback(onConnectionSettingsChanged)
    }
        
    func onConnectionSettingsChanged() {
        
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
    
    func restart() {
        
        if isFirstStart {
            return
        }
        
        if !isStarted {
            return
        }
        
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
                // Handle the error or retry as necessary
                return
            }
            
            print("Restarting: Stopped server; waiting 5 seconds")
            
            // Optionally, pause for necessary cleanup - adjust as needed
            Thread.sleep(forTimeInterval: 5.0)

            print("Restarting: Finished waiting")
            
            self.isStarted = false
            
            self.start()
        }
    }
    
}
