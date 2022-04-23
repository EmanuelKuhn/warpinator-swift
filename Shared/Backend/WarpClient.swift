//
//  WarpClient.swift
//  warpinator-project
//
//  Created by Emanuel on 13/02/2022.
//

import Foundation

import GRPC
import NIOCore
import NIOPosix

import NIOTransportServices

import NIOSSL

//let eventLoopGroup = PlatformSupport.makeEventLoopGroup(loopCount: System.coreCount)

func makeWarpClient(
    host: String,
    port: Int,
    pinnedCertificate: [UInt8],
    hostnameOverride: String,
    group: EventLoopGroup,
    connectivityStateDelegate: ConnectivityStateDelegate?=nil
) throws -> WarpAsyncClient {
    
    print("makeWarpClient(\(host), \(port), \(hostnameOverride)")
    
    let nioCertificate = try NIOSSLCertificate(bytes: pinnedCertificate, format: .pem)
    
    
    let pinnedPublicKey = try nioCertificate.extractPublicKey().toSPKIBytes()
    
    
    
    let tlsConfig: GRPCTLSConfiguration = .makeClientConfigurationBackedByNIOSSL(
        certificateChain: [],
        privateKey: nil,
        trustRoots: .default,
        certificateVerification: .fullVerification,
        hostnameOverride: hostnameOverride,
        customVerificationCallback: { cert, eventLoopVerification in
            
            
            NSLog("inside of customVerificationCallback")
            
            // Extract the leaf certificate's public key,
            // then compare it to the one you have.
            if let leaf = cert.first,
               let publicKey = try? leaf.extractPublicKey() {
                
                guard let certSPKI = try? publicKey.toSPKIBytes() else {
                    print("unable to extract spkibytes unableToValidateCertificate custom verification")
                    
                    eventLoopVerification.fail(NIOSSLError.unableToValidateCertificate)
                    
                    return
                }
                
                if pinnedPublicKey == certSPKI {
                    
                    NSLog("succeed custom verification")
                    eventLoopVerification.succeed(.certificateVerified)
                } else {
                    
                    print("pinnedCertificate != certSPKI unableToValidateCertificate custom verification")
                    
                    print(certSPKI)
                    
                    print(pinnedPublicKey)
                    
                    eventLoopVerification.fail(NIOSSLError.unableToValidateCertificate)
                }
            } else {
                
                print("NIOSSLError.noCertificateToValidate custom verification")
                eventLoopVerification.fail(NIOSSLError.noCertificateToValidate)
            }
        }
    )
    
    let clientConnection: ClientConnection.Builder = ClientConnection.usingTLS(with: tlsConfig, on: group)
    
    clientConnection.withConnectivityStateDelegate(connectivityStateDelegate)
    
    let channel: GRPCChannel = clientConnection.connect(host: host, port: port)
    
    return WarpAsyncClient(channel: channel)
}
