//
//  NetworkUtils.swift
//  warpinator-project
//
//  Created by Emanuel on 20/03/2022.
//

import Foundation
import Network

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
