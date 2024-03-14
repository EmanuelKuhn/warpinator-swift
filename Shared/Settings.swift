//
//  Settings.swift
//  warpinator-project
//
//  Created by Emanuel on 19/03/2023.
//

import Foundation
import SwiftProtobuf
import Accelerate

protocol WarpSettings {

    var identity: String { get }
    
    var port: Int { get }
    var authPort: Int { get }
    
    var groupCode: String { get set }
    
    func addOnConnectionSettingsChangedCallback(_: @escaping () -> Void)
}

enum WarpSettingsKey: String {
    case port, authPort, groupcode
}

extension WarpSettingsKey {
    func get<T>(defaultValue: T) -> T {
        if let value = UserDefaults.standard.object(forKey: rawValue) as? T {
            return value
        }
        
        return defaultValue
    }
    
    func set<T>(newValue: T) {
        UserDefaults.standard.set(newValue, forKey: rawValue)
    }
}

class WarpSetingsUserDefaults: WarpSettings {
    
    static var shared = WarpSetingsUserDefaults()
    
    var connectionSettingsChangedCallbacks: [() -> ()] = []
    
    func addOnConnectionSettingsChangedCallback(_ callback: @escaping () -> Void) {
        connectionSettingsChangedCallbacks.append(callback)
    }

    
    var identity: String {
        return WarpSetingsUserDefaults.getIdentity(hostName: NetworkConfig.shared.hostname)
    }
    
    var port: Int {
        get { return WarpSettingsKey.port.get(defaultValue: 42000) }
        set {
            WarpSettingsKey.port.set(newValue: newValue)
            
            signalConnectionSettingsChanged()
        }
    }
    
    var authPort: Int {
        get { return WarpSettingsKey.authPort.get(defaultValue: 42001) }
        set {
            WarpSettingsKey.authPort.set(newValue: newValue)
            
            signalConnectionSettingsChanged()
        }
    }
    
    var groupCode: String {
        get { return WarpSettingsKey.groupcode.get(defaultValue: DEFAULT_GROUP_CODE) }
        set {
            WarpSettingsKey.groupcode.set(newValue: newValue)
            
            signalConnectionSettingsChanged()
        }
    }

    private func signalConnectionSettingsChanged() {
        DispatchQueue.global().async {
            self.connectionSettingsChangedCallbacks.forEach { $0() }
        }
    }
    
    
    static func getIdentity(hostName: String) -> String {
        
        let key = "identity"
        
        if UserDefaults.standard.string(forKey: key) == nil {
            let newIdentity = Auth.computeIdentity(hostName: hostName)
            UserDefaults.standard.set(newIdentity, forKey: key)
        }
        
        return UserDefaults.standard.string(forKey: key)!
    }
}
