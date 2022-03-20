//
//  Auth.swift
//  warpinator-project
//
//  Created by Emanuel on 09/02/2022.
//

import Foundation

import CryptoKit
import Sodium

import Shield
import ShieldSecurity

let DEFAULT_GROUP_CODE = "Warpinator"

enum AuthError: Error {
    case invalidGroupKey
    case failedProcessingRemoteCertificate(_ message: String)
    case failedToOpenSecretBox
}

let hour_in_seconds: TimeInterval = TimeInterval(3600)
let day_in_seconds = 24 * hour_in_seconds

class Auth {
    
    struct ServerIdentity {
        let certificate: SecCertificate
        let keyPair: SecKeyPair
    }
    
    let expire_time = 30 * day_in_seconds
    
    let hostName: String
        
    private(set) lazy var identity: String = {
        computeIdentity(hostName: self.hostName)
    }()
    
    var groupCode: String
    
    var serverIdentity: ServerIdentity!
    
    init(hostName: String, groupCode: String = DEFAULT_GROUP_CODE) throws {
        self.hostName = hostName
        
        self.groupCode = groupCode
        
        self.serverIdentity = try makeServerKeys()
    }
    
    func makeServerKeys() throws -> ServerIdentity {
                
        let secKeyPair = try ShieldSecurity.SecKeyPair.Builder(type: .rsa, keySize: 2048).generate()
        
        let subjectName = try NameBuilder().add(self.hostName, forTypeName: "CN").name
        let issuerName = try NameBuilder().add(self.hostName, forTypeName: "CN").name
        
        let validity = DateInterval.init(start: Date.init(timeIntervalSinceNow: -day_in_seconds), duration: expire_time + day_in_seconds)
        
        let certificate = try ShieldX509.Certificate.Builder()
            .subject(name: subjectName)
            .issuer(name: issuerName)
            .valid(from: validity.start, to: validity.end)
            .serialNumber(ShieldX509.Certificate.Builder.randomSerialNumber())
            .publicKey(publicKey: secKeyPair.publicKey, usage: nil)
            //TODO: If neeeded add ipv4 address as altname
            .build(signingKey: secKeyPair.privateKey, digestAlgorithm: .sha256)
        
        print(certificate.tbsCertificate.subject)
        
        print(Auth.pemEncoded(certificate: try certificate.sec()!))
        
        let secCertificate = try certificate.sec()!
        
        return .init(certificate: secCertificate, keyPair: secKeyPair)
    }
    
    static func pemEncoded(certificate: SecCertificate) -> String {
        let begin = "-----BEGIN CERTIFICATE-----\n"
        let end = "\n-----END CERTIFICATE-----\n"
        
        let derBytes: Data = certificate.derEncoded
        
        let base64Encoded = derBytes.base64EncodedString(options: [.lineLength64Characters,  .endLineWithLineFeed])
        
        return begin + base64Encoded + end
    }
    
    func getLockedCertificate() throws -> String {
                
        let pemEncodedCert = Auth.pemEncoded(certificate: self.serverIdentity.certificate)
        
        let groupKey = try SecretBox.Key(deriveGroupKey())
        
        let sodium = Sodium()
        
        let sealedCertificate = Data(sodium.secretBox.seal(message: pemEncodedCert.bytes, secretKey: groupKey)!)
                
        return sealedCertificate.base64EncodedString()
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
