//
//  Discovery.swift
//  warpinator-project
//
//  Created by Emanuel on 11/02/2022.
//
// This file contains classes for mDNS discovery of peers

import Foundation

import OSLog
import Network

struct DiscoveryConfig {
    let identity: String
    
    let api_version: String
    let auth_port: Int
    let hostname: String
}

struct MDNSPeer: Peer {
    
    let domain: String
    let type: String
    let name: String
    
    var hostName: String {
        return txtRecord["hostname"] ?? "0.0.0.0"
    }
        
    /// I noticed that when caching the result of resolving the dns name, and trying to use it some time later,
    /// the name would not resolve to an ip address when using it to connect with .hostandport untill a new
    /// `dns-sd -L` type lookup query is send. Thus it is easier to always resolve the domain, type, name combination to a
    /// dns name host and immediately use the result to start a network connection.
    func resolve() async throws -> (String, Int) {
        return try await BonjourResolver.resolve(service: .init(domain: domain, type: type, name: name))
    }
    
    let txtRecord: NWTXTRecord
        
    var authPort: Int? {
        return Int(txtRecord.dictionary["auth-port"] ?? "nil")
    }
    
    var fetchCertInfo: FetchCertInfo? {
        guard let port = authPort else {
            return nil
        }
        
        return .authPort(port)
    }
}

extension MDNSPeer {
    static func fromResult(_ result: NWBrowser.Result) -> MDNSPeer? {
        precondition(Thread.isMainThread)
        
        guard case let .service(name, type, domain, _) = result.endpoint else {
            return nil
        }
        
        guard case let .bonjour(txtRecord) = result.metadata else {
            return nil
        }
        
        let peer = MDNSPeer(domain: domain, type: type, name: name, txtRecord: txtRecord)
        
        return peer
    }
}

/// Class that both browses zeroconf peers, as well as advertises this warpinator instance using zeroconf
class BonjourDiscovery: PeerDiscovery {
    
    let config: DiscoveryConfig
    
    private var listener: NWListener?
    private var browser: NWBrowser?
    
    init(config: DiscoveryConfig) {
        self.config = config
    }

    
    // MARK: Respond to browse results
    
    private var onRemoteChangedListeners: Array<RemoteChangeListener> = []

    func addOnRemoteChangedListener(_ listener: @escaping RemoteChangeListener) {
        self.onRemoteChangedListeners.append(listener)
    }
    
    private func onRemotesChanged(_ change: RemoteChanged) {
        onRemoteChangedListeners.forEach({
            $0(change)
        })
    }
        
    private func addOrUpdatePeer(peer: MDNSPeer) {
        if peer.txtRecord["type"] != "flush" {
            self.onRemotesChanged(.added(peer: peer))
        }
    }
    
    private func removePeer(name: String) {
        self.onRemotesChanged(.removed(name: name))
    // MARK: Setup zeroconf browser
    }
    
    
    func setupBrowser() {
        
        let params = NWParameters()
        params.includePeerToPeer = true
        
        
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_warpinator._tcp", domain: nil), using: params)
        
        self.browser = browser
        
        browser.stateUpdateHandler = { newState in
            
            switch newState {
            case .failed(let error):
                browser.cancel()
                // Handle restarting browser
                os_log("Browser - failed with %{public}@, restarting", error.localizedDescription)
            case .ready:
                os_log("Browser - ready")
            case .setup:
                os_log("Browser - setup")
            default:
                break
            }
        }
        
        browser.browseResultsChangedHandler = { [self] results, changes in
            
            precondition(Thread.isMainThread)
            
            for change in changes {
                print("\n Change: \(change)")
                
                switch change {
                case .identical:
                    print("discovery .identical: consider handling")
                case .added(let mdns_result):
                    let peer = MDNSPeer.fromResult(mdns_result)
                    
                    if let peer = peer {
                        print("discovery .added addOrUpdate \(mdns_result)")
                        
                        self.addOrUpdatePeer(peer: peer)
                    } else {
                        print("discovery ignored .added \(mdns_result)")
                    }
                    
                case .changed(old: let old, new: let new, flags: let flags):
                    
                    print("discovery .changed \(flags)")

                    switch(flags) {
                    case .metadataChanged:
                        let peer = MDNSPeer.fromResult(new)
                        
                        if let peer = peer {
                            print("discovery .change addOrUpdate \(new)")
                            
                            self.addOrUpdatePeer(peer: peer)
                        } else {
                            print("discovery ignored .changed \(new)")
                        }
                    default:
                        print("discovery .changed ignored because of flags: \(flags)")
                    }
                    
                    
                case .removed(let removed_result):
                    print("discovery .removed: \(removed_result)")
                    
                    guard case let .service(name, _, _, _) = removed_result.endpoint else {
                        print("Expected endpoint to be .service but was \(removed_result.endpoint)")
                        
                        return
                    }
                    
                    self.removePeer(name: name)
                    
                @unknown default:
                    print("discovery unkown default")
                }
                
            }
            
        }
                
        // Start browsing and ask for updates on the main queue.
        browser.start(queue: .main)
    }
    
    // MARK: Advertise this instance with listener
    
    
    // The txtRecord to advertise with
    private var txtRecord: NWTXTRecord {
        return NWTXTRecord(["api-version": config.api_version, "auth-port": String(config.auth_port), "hostname": config.hostname, "type": "real"])
    }
        
    func setupListener(port: UInt16 = 42000) {
        
        if let listener = listener {
            listener.cancel()
        }
        
        print("setting up NWListener")
        
        /// Has to be udp to be able to start while the WarpServer is already running on the same port.
        /// (As WarpServer uses tcp for transport).
        let params = NWParameters.udp
        params.includePeerToPeer = true
        
        listener = try! NWListener(using: params, on: NWEndpoint.Port(integerLiteral: port))
        
        let listener = self.listener!
        
            
        listener.stateUpdateHandler = { newState in
            switch newState {
            case .ready:
                if let port = listener.port {
                    // Listener setup on a port.  Active browsing for this service.
                    os_log(".ready \(port.debugDescription)")
                }
            case .failed(let error):
                
                listener.cancel()
                os_log("Listener - failed with %{public}@, restarting", error.localizedDescription)
                
                // Handle restarting listener
            default:
                os_log(".default")
                break
            }
        }
        
        // Used for receiving a new connection for a service.
        // This is how the connection gets created and ultimately receives data from the browsing device.
        listener.newConnectionHandler = { newConnection in
            os_log("new conn \(newConnection.debugDescription)")
            // Send newConnection (NWConnection) back on a delegate to set it up for sending/receiving data
        }
        
        // Start listening, and request updates on the main queue.
        listener.start(queue: .main)
        
        listener.service = NWListener.Service(name: config.identity,
                                              type: "_warpinator._tcp",
                                              txtRecord: txtRecord)

        
        print("started listening")
        
    }
}
