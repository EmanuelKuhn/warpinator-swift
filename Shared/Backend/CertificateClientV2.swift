//
//  CertificateClientV2.swift
//  warpinator-project
//
//  Created by Emanuel on 12/02/2022.
//

import Foundation

import GRPC
import NIOCore
import NIOPosix


func fetchCertV2(host: String, auth_port port: Int, regRequest: RegRequest) throws -> RegResponse? {
    let group = PlatformSupport.makeEventLoopGroup(loopCount: 1)
    defer {
      try? group.syncShutdownGracefully()
    }

    // Make a client, make sure we close it when we're done.
    let client = try makeClient(host: host, port: port, group: group)
    defer {
      try? client.channel.close().wait()
    }
    
    client.defaultCallOptions.timeLimit = .timeout(.seconds(5))
    
    return getCert(using: client, regRequest: regRequest)

}

private func getCert(using client: WarpRegistrationClient, regRequest: RegRequest) -> RegResponse? {
    print("→ getCert")
    
    let call = client.requestCertificate(regRequest)
    
    let regResponse: RegResponse

    do {
        regResponse = try call.response.wait()
    } catch {
        print("RPC failed: \(error)")
        return nil
    }
    
    return regResponse
}

private func makeClient(host: String, port: Int, group: EventLoopGroup) throws -> WarpRegistrationClient {
    
//    let socketAddress = try SocketAddress.makeAddressResolvingHost(host, port: port)
    
//    print("socketAddress: \(String(describing: socketAddress))")
    

    let channel = try GRPCChannelPool.with(
//        target: .socketAddress(socketAddress),
        target: .host(host, port: port),
        transportSecurity: .plaintext,
        eventLoopGroup: group
    )
    
    

  return WarpRegistrationClient(channel: channel)
}
