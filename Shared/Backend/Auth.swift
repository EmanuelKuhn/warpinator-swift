//
//  Auth.swift
//  warpinator-project
//
//  Created by Emanuel on 09/02/2022.
//

import Foundation

import CryptoKit
import Sodium

let DEFAULT_GROUP_CODE = "Warpinator"

enum AuthError: Error {
    case invalidGroupKey
    case failedProcessingRemoteCertificate(_ message: String)
    case failedToOpenSecretBox
}

class Auth {
    
    let hostName: String
        
    private(set) lazy var identity: String = {
        computeIdentity(hostName: self.hostName)
    }()
    
    var groupCode: String
    
    init(hostName: String, groupCode: String = DEFAULT_GROUP_CODE) {
        self.hostName = hostName
        
        self.groupCode = groupCode
    }
    
    func getCert() -> String {
        return "dummy cert \(Foundation.ProcessInfo().hostName)"
    }
    
    private func computeIdentity(hostName: String) -> String {
        return "\(hostName.uppercased())-\(UUID().uuidString)"
    }
    
    func deriveGroupKey() throws -> SHA256Digest {
        
        guard let codeData = groupCode.data(using: .utf8) else {
            throw AuthError.invalidGroupKey
        }
        
        return SHA256.hash(data: codeData)
    }
    
    func processRemoteCertificate(lockedCertificate: String) throws -> Bytes {
                        
        let decoded = Data(base64Encoded: lockedCertificate, options: .ignoreUnknownCharacters)!
        
        let bytes = Bytes(decoded)
        
        let keyBytes = try SecretBox.Key(deriveGroupKey())
        
        let sodium = Sodium()
        
        guard let result = sodium.secretBox.open(nonceAndAuthenticatedCipherText: bytes, secretKey: keyBytes) else {
            throw AuthError.failedToOpenSecretBox
        }
        
        return result
    }
}
