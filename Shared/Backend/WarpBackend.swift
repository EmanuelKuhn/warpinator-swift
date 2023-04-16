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
    static let shared = WarpBackend()
    
    private let settings: WarpSettings
    
    private let eventLoopGroup: EventLoopGroup
    
    private let auth: Auth
    private let discovery: BonjourDiscovery
    
    let remoteRegistration: RemoteRegistration
    
    var isStarted = false
    
    var isFirstStart = true
    
    private var certServer: CertServerV2? = nil
    private var warpServer: WarpServer? = nil
    
    private init() {
        
        self.settings = WarpSetingsUserDefaults.shared
        self.eventLoopGroup = PlatformSupport.makeEventLoopGroup(loopCount: 2)

        let networkConfig = NetworkConfig.shared
        
        self.auth = Auth(networkConfig: networkConfig, identity: settings.identity, groupCode: settings.groupCode)
        
        let discoveryConfig = DiscoveryConfig(identity: auth.identity, api_version: "2", auth_port: settings.authPort, hostname: networkConfig.hostname)

        self.discovery = BonjourDiscovery(config: discoveryConfig)
        
        self.remoteRegistration = RemoteRegistration(discovery: discovery, auth: auth, clientEventLoopGroup: eventLoopGroup)

//         Add callback for when connection settings change
        settings.addOnConnectionSettingsChangedCallback(onConnectionSettingsChanged)
        
        auth.groupCode
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
        let certServer = CertServerV2(auth: auth)
        self.certServer = certServer
        
        DispatchQueue.global(qos: .userInitiated).async {
            try? certServer.run(eventLoopGroup: self.eventLoopGroup)
        }
                
        let warpServer = WarpServer(auth: auth, remoteRegistration: self.remoteRegistration, port: settings.port)
        self.warpServer = warpServer
        
        DispatchQueue.global(qos: .userInitiated).async {
            try? warpServer.run(eventLoopGroup: self.eventLoopGroup)
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
        
        DispatchQueue.global(qos: .userInitiated).async {
            try! self.warpServer?.close()
            self.warpServer = nil
            
            self.discovery.pauseBonjour()

            self.auth.regenerateCertificate()
            
            DispatchQueue.main.asyncAfter(deadline: .now()) {
                print("Starting servers again...")
                                        
                let warpServer = WarpServer(auth: self.auth, remoteRegistration: self.remoteRegistration, port: self.settings.port)
                self.warpServer = warpServer
                
                DispatchQueue.global(qos: .userInitiated).async {
                    try? warpServer.run(eventLoopGroup: self.eventLoopGroup)
                }

                DispatchQueue.global(qos: .userInitiated).async {
                    self.discovery.restartBonjour()
                }
                
                self.isStarted = true
            }
        }
    }
    
}
