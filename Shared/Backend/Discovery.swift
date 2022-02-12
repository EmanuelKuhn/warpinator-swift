//
//  Discovery.swift
//  warpinator-project
//
//  Created by Emanuel on 11/02/2022.
//

import Foundation

import OSLog
import Network

struct DiscoveryConfig {
    let api_version: String
    let auth_port: Int
    let hostname: String
}

struct MDNSPeer {
    /// The resolved DNS name
//    var resolvedDNSName: String
    
    let domain: String
    let type: String
    let name: String
    
//    let resolvedDNSName: String
    
    /// I noticed that when caching the result of resolving the dns name, and trying to use it some time later,
    /// the name would not resolve to an ip address when using it to connect with .hostandport untill a new
    /// `dns-sd -L` type lookup query is send. Thus it is easier to always resolve the domain, type, name combination to a
    /// dns name host and immidiatly use the result to start a network connection.
    func resolveDNSName(callback: @escaping (Result<(String, Int), Error>) -> Void) {
        
        DispatchQueue.main.async {
            BonjourResolver.resolve(service: .init(domain: domain, type: type, name: name)) { result in
                DispatchQueue.global().async {
                    callback(result)
                }
            }
        }
    }
    
    func resolveDNSName() async throws -> (String, Int) {
        return try await BonjourResolver.resolve(service: .init(domain: domain, type: type, name: name))
    }
    
    let txtRecord: NWTXTRecord
    
    var active = true
    
    var authPort: Int? {
        return Int(txtRecord.dictionary["auth_port"] ?? "nil")
    }
    
    func computeKey() -> String {
        return "\(domain) \(type) \(name)"
    }
}


class Discovery {
    
    let config: DiscoveryConfig
    
    private var listener: NWListener?
    private var browser: NWBrowser?
    
    var remotes: Array<MDNSPeer> {
        return Array(self.peers.values)
    }
    
    private var peers: Dictionary<String, MDNSPeer>
    
    private var onRemotesChangedListeners: Array<() -> Void> = []

    func addOnRemotesChangedListener(_ listener: @escaping () -> Void) {
        self.onRemotesChangedListeners.append(listener)
    }
    
    private func onRemotesChanged() {
        onRemotesChangedListeners.forEach({
            $0()
        })
    }
    
    init(config: DiscoveryConfig) {
        self.config = config
        
        self.peers = .init()
    }
    
    private func addPeer(peer: MDNSPeer) {
        self.peers[peer.computeKey()] = peer
        
        self.onRemotesChanged()
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
                    print("discovery .added \(mdns_result)")

                    precondition(Thread.isMainThread)
                    
                    guard case let .service(name, type, domain, _) = mdns_result.endpoint else {
                        print("Expected endpoint to be .service but was \(mdns_result.endpoint)")
                        
                        return
                    }
                    
                    guard case let .bonjour(txtRecord) = mdns_result.metadata else {
                        print("could not get txtrecord")
                        return
                    }
                    
                    let peer = MDNSPeer(domain: domain, type: type, name: name, txtRecord: txtRecord)
                    
                    self.addPeer(peer: peer)
                    
                case .removed(let removed_result):
                    print("discovery .removed: \(removed_result)")
                case .changed(old: let old, new: let new, flags: let flags):
                    print("discovery .changed \(old), \(new), \(flags)")
                @unknown default:
                    print("discovery unkown default")
                }
                
            }
            
        }
                
        // Start browsing and ask for updates on the main queue.
        browser.start(queue: .main)
        
        
    }
    
    func setupListener() {
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        
        let listener = try! NWListener(using: params, on: 42000)
        
        self.listener = listener
        
        let txtRecord =  NWTXTRecord(["api-version": config.api_version, "auth-port": String(config.auth_port), "hostname": config.hostname, "type": "real"])
        
        listener.service = NWListener.Service(name: "IOS-UID",
                                              type: "_warpinator._tcp",
                                              txtRecord: txtRecord)
        
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
        
        print("started listening")
        
    }
}
