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


struct ContentView: View {
    
    @State var string = "certificate"
    
    @State var clientAddress = "192.168.0.100"
    
    let auth: Auth
    let warp: WarpBackend
    
    @ObservedObject var discoveryViewModel: DiscoveryViewModel
    
    
    init(warp: WarpBackend) {
        
        self.auth = warp.auth
        self.warp = warp
        
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
                            
                        }
                    }
                }
                
                
                Button("start servers (certv2 and warpserver)", action: {
                    let certServer = CertServerV2(auth: auth)
                                        
                    DispatchQueue.global(qos: .userInitiated).async {
                        try? certServer.run()
                    }
                    
                    let warpServer = WarpServer(auth: auth, remoteRegistration: warp.remoteRegistration)
                    
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
            }
        }
        
        
    }
}

//struct ContentView_Previews: PreviewProvider {
//    static var previews: some View {
//        ContentView()
//    }
//}



