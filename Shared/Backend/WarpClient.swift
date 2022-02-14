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

typealias WarpRPCCallFunc<I, O> = (WarpClient) -> (UnaryCall<I, O>)

actor WarpGRPCClient {

    enum WarpError: Error {
        case connectionError
    }
    
    enum State {
        case initializing
        case connected
        case stale
    }
    
    var state: State = .initializing
    
    let group: EventLoopGroup
    let client: WarpClient
    
    init(host: String, port: Int, pinnedCertificate: [UInt8], hostnameOverride: String) throws {
        self.group = PlatformSupport.makeEventLoopGroup(loopCount: 1)

        self.client = try makeWarpClient(host: host, port: port, pinnedCertificate: pinnedCertificate, hostnameOverride: hostnameOverride, group: group)
        
        self.state = .connected
    }
    
    deinit {
        try? client.channel.close().wait()
            
        try? self.group.syncShutdownGracefully()
    }
    
    func rpcCall<I, O>(rpcCall: WarpRPCCallFunc<I, O>) throws -> O {
        let call = rpcCall(client)
        
        do {
            return try call.response.wait()
        } catch is NIOTSError {
            self.state = .stale
            
            throw WarpError.connectionError
        } catch {
            print("rpcCall: uncaught error: \(error)")
            
            throw error
        }
    }

}

//func warpRPCCall<I, O>(host: String, port: Int, pinnedCertificate: [UInt8], hostnameOverride: String, rpcCall: WarpRPCCallFunc<I, O>) throws -> O? {
//    let group = PlatformSupport.makeEventLoopGroup(loopCount: 1)
//    defer {
//      try? group.syncShutdownGracefully()
//    }
//    
//    NSLog("rpc call created group")
//
//    // Make a client, make sure we close it when we're done.
//    let client = try makeWarpClient(host: host, port: port, pinnedCertificate: pinnedCertificate, hostnameOverride: hostnameOverride, group: group)
//    defer {
//      try? client.channel.close().wait()
//    }
//    
//    NSLog("rpc call created  client")
//        
//    let call = rpcCall(client)
//    
//    NSLog("rpc call waiting for response")
//    
//    let res = try? call.response.wait()
//    
//    NSLog("Got result")
//    
//    return res
//}

private func makeWarpClient(host: String, port: Int, pinnedCertificate: [UInt8], hostnameOverride: String, group: EventLoopGroup) throws -> WarpClient {
            
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
        
    let clientConnection = ClientConnection.usingTLS(with: tlsConfig, on: group)
//        .withTLSCustomVerificationCallback()
    

    
    let channel: GRPCChannel = clientConnection.connect(host: host, port: port)
        
    return WarpClient(channel: channel)
}
