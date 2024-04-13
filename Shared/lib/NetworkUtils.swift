//
//  NetworkUtils.swift
//  warpinator-project
//
//  Created by Emanuel on 20/03/2022.
//

import Foundation
import Network

import os

struct IFAddress {
    let interfaceName: String
    let ipAddress: IPAddress
}

// Adapted from: https://stackoverflow.com/a/56342010
func getIFAddresses() -> [IFAddress] {
    var addresses: [IFAddress] = []
    
    var ifaddr: UnsafeMutablePointer<ifaddrs>? = nil
    
    if getifaddrs(&ifaddr) == 0 {
        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            
            guard let interface = ptr?.pointee else { return [] }
            
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) || addrFamily == UInt8(AF_INET6) {

                let ifName: String = String(cString: (interface.ifa_name))

                var address = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                
                getnameinfo(interface.ifa_addr, socklen_t((interface.ifa_addr.pointee.sa_len)), &address, socklen_t(address.count), nil, socklen_t(0), NI_NUMERICHOST)
                
                let addressString = String(cString: address)
                                
                let ipAddress: IPAddress
                
                if addrFamily == UInt8(AF_INET) {
                    ipAddress = IPv4Address(addressString)!
                } else {
                    ipAddress = IPv6Address(addressString)!
                }
                
                addresses.append(.init(interfaceName: ifName, ipAddress: ipAddress))
            }
        }
        
        freeifaddrs(ifaddr)
    }
    
    return addresses
}


func requestLocalNetworkPermissionAsync(timeout: Double) async -> Bool {
    return await withCheckedContinuation { continuation in
        DispatchQueue.global().async {
            let hasPermission = requestLocalNetworkPermission(timeout: timeout)
            continuation.resume(returning: hasPermission)
        }
    }
}


func requestLocalNetworkPermission(timeout: Double) -> Bool {
    
    var canDiscoverSelf = false
    
    let semaphore = DispatchSemaphore(value: 0)
    
    let browserParams = NWParameters()
    browserParams.includePeerToPeer = false
    
    let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_warpinator._tcp", domain: nil), using: browserParams)
    
    browser.stateUpdateHandler = { newState in
        
        switch newState {
        case .failed(_):
            
            // Signal that something failed and we can stop waiting
            canDiscoverSelf = false
            semaphore.signal()
        default:
            break
        }
    }
    
    browser.browseResultsChangedHandler = { results, changes in
        if results.count >= 1 {
            // Signal that we found a remote (probably ourselves) and can stop waiting
            canDiscoverSelf = true
            semaphore.signal()
        }
    }
    
    // Start browsing and ask for updates on a background queue.
    browser.start(queue: .global())
    
    
    let listenerParams = NWParameters.udp
    listenerParams.includePeerToPeer = true
    
    let listener: NWListener
    
    do {
        listener = try NWListener(using: listenerParams)
    } catch {
        os_log("Failed to create NWListener: \(error.localizedDescription)")
        
        return false
    }
        
    listener.stateUpdateHandler = { newState in
        switch newState {
        case .ready:
            break
        case .failed(_):
            // Signal that something failed and we can stop waiting
            canDiscoverSelf = false
            semaphore.signal()
        default:
            break
        }
    }
    
    listener.newConnectionHandler = { _ in }
                
    listener.service = NWListener.Service(name: "test service",
                                          type: "_warpinator._tcp",
                                          txtRecord: NWTXTRecord(["type": "flush"]))
    
    // Start listening, and request updates on a background queue.
    listener.start(queue: .global())
    
    let _ = semaphore.wait(timeout: .now() + timeout)
    
    browser.cancel()
    listener.cancel()
    
    return canDiscoverSelf
}



