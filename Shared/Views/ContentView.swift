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

#if !canImport(UIKit)
import AppKit
#endif

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
        
        print("running with config: \(warp.discovery.config)")
    }
    
    @State private var showingSheet = false
    
    @State private var urls: [URL] = []

    @State private var currentRemote: DiscoveryViewModel.VMRemote? = nil

    
    var body: some View {
        
        ScrollView {
            VStack {
                TextField("client: ", text: $clientAddress)
                
                Text(string)
                    .padding()
                
                VStack {
                    ForEach(discoveryViewModel.remotes) { remote in
                        Button("Remote: \(remote.title)") {
                            #if canImport(UIKit)

                            showingSheet.toggle()

                            #else
                            let panel = NSOpenPanel()
                            panel.allowsMultipleSelection = true
                            panel.canChooseDirectories = false
                            if panel.runModal() == .OK {
                                self.urls = panel.urls
                            }

                            Task {
                                await currentRemote?.onTapFunc(urls: urls)
                            }
                            
                            #endif
                            
                            currentRemote = remote
                            
                        }
                        .sheet(isPresented: $showingSheet, onDismiss: {
                            print("sheet dismissed")
                            
                            Task {
                                await currentRemote?.onTapFunc(urls: urls)
                            }
                            
                        }, content: {
                            #if canImport(UIKit)
                            DocumentPicker(urls: $urls)
                            #else
                            Text("Can't use DocumentPicker")
                            Button("Dismiss") {
                                showingSheet.toggle()
                            }
                            #endif
                        })
                    }
                }
                
                
                Button("start servers (certv2 and warpserver)", action: {
                    let certServer = CertServerV2(auth: auth)
                                        
                    DispatchQueue.global(qos: .userInitiated).async {
                        try? certServer.run(eventLoopGroup: warp.eventLoopGroup)
                    }
                    
                    let warpServer = WarpServer(auth: auth, remoteRegistration: warp.remoteRegistration)
                    
                    DispatchQueue.global(qos: .userInitiated).async {
                        try? warpServer.run(eventLoopGroup: warp.eventLoopGroup)
                    }
                    
                })
                
                Button("start discovery", action: {
                    
                    DispatchQueue.global(qos: .userInitiated).async {
                        warp.discovery.setupListener()
                        
                        print("setup listener done")
                        
                        warp.discovery.setupBrowser()
                        
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



