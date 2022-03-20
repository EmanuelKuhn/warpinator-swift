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
        get {
            return ProcessInfo().hostName
        }
    }
    
    var ipAddresses: [IPAddress] {
        let ifAddresses = getIFAddresses()
        
        return ifAddresses
            .filter({$0.interfaceName.starts(with: "en")})
            .map({$0.ipAddress})
    }
    
}
