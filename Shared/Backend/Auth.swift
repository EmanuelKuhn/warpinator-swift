//
//  Auth.swift
//  warpinator-project
//
//  Created by Emanuel on 09/02/2022.
//

import Foundation

struct Auth {
    func getCert() -> String {
        return "dummy cert \(Foundation.ProcessInfo().hostName)"
    }
}
