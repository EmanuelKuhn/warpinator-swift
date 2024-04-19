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
    }
    
    func start() async throws {
        var initializationSuccessfull = false
        
        // Start servers
        let certServer = CertServerV2(auth: auth, auth_port: settings.authPort)
        self.certServer = certServer
                
        do {
            try await certServer.runAsync(eventLoopGroup: self.eventLoopGroup)
        } catch {
            throw "Failed to start cert server: \(error.localizedDescription)"
        }
        
        defer {
            if !initializationSuccessfull {
                try? certServer.close()
            }
        }
                
        let warpServer = WarpServer(auth: auth, remoteRegistration: self.remoteRegistration, port: settings.port)
        self.warpServer = warpServer
        
        try await warpServer.runAsync(eventLoopGroup: self.eventLoopGroup)
        
        defer {
            if !initializationSuccessfull {
                try? warpServer.close()
            }
        }
        
        // Start bonjour discovery
        self.discovery.setupBrowser()

        print("setup browser")

        self.discovery.setupListener(port: UInt16(self.settings.port))

        print("setup listener done")
        
        initializationSuccessfull = true

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
        
        self.discovery.cancelBonjour()
        
        try? self.warpServer?.close()
        self.warpServer = nil
        
        try? self.certServer?.close()
        self.certServer = nil
    }
    
    deinit {
        print("WarpBackend.denit() called")
        stop()
        
        try? self.eventLoopGroup.syncShutdownGracefully()
    }
}
