//
//  NetworkConfig.swift
//  warpinator-project
//
//  Created by Emanuel on 20/03/2022.
//

import Foundation
import Network

class NetworkConfig {
    
    var hostname: String {
        return ProcessInfo().hostName
    }
    
    var ipAddresses: [IPAddress] {
        let ifAddresses = getIFAddresses()
        
        return ifAddresses
            .filter({$0.interfaceName.starts(with: "en") || $0.interfaceName.starts(with: "bridge")})
            .map({$0.ipAddress})
    }
    
}
