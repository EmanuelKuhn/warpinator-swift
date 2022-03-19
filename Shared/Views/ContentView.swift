//
//  ContentView.swift
//  Shared
//
//  Created by Emanuel on 09/02/2022.
//

import SwiftUI

//import WarpGRPC

import Foundation

import NIOCore
import NIOPosix
import GRPC



//let address = Foundation.ProcessInfo().hostName

struct ContentView: View {
    
    @State var string = "certificate"
    
    @State var clientAddress = "192.168.0.100"
    
    let auth: Auth
    
    let warp: WarpBackend
    
    @ObservedObject var discoveryViewModel: DiscoveryViewModel
    
    
    init() {
        
        let hostName = Foundation.ProcessInfo().hostName
        
        auth = Auth(hostName: hostName)
        
        warp = WarpBackend.from(
            discoveryConfig: .init(identity: auth.identity, api_version: "2", auth_port: 42001, hostname: hostName),
            auth: auth
        )
        
        discoveryViewModel = .init(warp: warp)
        
        print("running with config: \(warp.remoteRegistration.discovery.config)")
    }
    
    
    var body: some View {
        
        ScrollView {
            VStack {
                TextField("client: ", text: $clientAddress)
                
                Text(string)
                    .padding()
                
                VStack {
                    ForEach(discoveryViewModel.remotes) { remote in
                        Button("Remote: \(remote.title)") {
                            
                            Task {
                                await remote.onTapFunc()
                            }
                            
                            
//                            DispatchQueue.global(qos: .default).async {
//                                Task {
//                                    let resolveResult = try? await remote.peer.resolveDNSName()
//
//                                    guard let (host, _) = resolveResult else {
//                                        print("failed to resolve")
//                                        return
//                                    }
//
//                                    print("sucessfully resolved: \(host)")
//
//                                    DispatchQueue.global(qos: .background).async {
//                                        let result = try? fetchCertV2(host: host, auth_port: 42001, regRequest: RegRequest.with({
//                                            $0.hostname = warp.remoteRegistration.discovery.config.hostname
//                                        }))
//
//                                        print("Got result: \(result?.lockedCert ?? "nil")")
//
//                                        Task { @MainActor in
//                                            if let lockedCert = result?.lockedCert {
//                                                self.string = lockedCert
//                                            } else {
//                                                self.string = "failed"
//                                            }
//                                        }
//
//                                    }
//                                }
//                            }
                        }
                    }
                }
                
                
                Button("start servers (certv2 and warpserver)", action: {
                    let certServer = CertServerV2(auth: auth)
                                        
                    DispatchQueue.global(qos: .userInitiated).async {
                        try? certServer.run()
                    }
                    
                    let warpServer = WarpServer(auth: auth)
                    
                    DispatchQueue.global(qos: .userInitiated).async {
                        try? warpServer.run()
                    }
                    
                })
                
                Button("start discovery", action: {
                    
                    DispatchQueue.global(qos: .userInitiated).async {
                        warp.remoteRegistration.discovery.setupListener()
                        
                        print("setup listener done")
                        
                        warp.remoteRegistration.discovery.setupBrowser()
                        
                        print("setup browser")
                    }
                })
                
                Button("print peers", action: {
//                    for remote in warp.remoteRegistration.discovery.remotes {
//                        print("\n")
//
//                        print(remote)
//
//                        //                        let socketAddress = try? SocketAddress.makeAddressResolvingHost(remote.resolvedDNSName, port: Int(remote.txtRecord["auth-port"] ?? "") ?? 42001)
//                    }
                })
            }
        }
        
        
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}



