//
//  ContentView.swift
//  Shared
//
//  Created by Emanuel on 09/02/2022.
//

import SwiftUI

import Foundation

import NIOCore
import NIOPosix
import GRPC

#if !canImport(UIKit)
import AppKit
#endif

struct ContentView: View {
    let warp: WarpBackend
    
    init(warp: WarpBackend) {
        self.warp = warp
    }
    
//    // File picker
//    @State private var showingSheet = false
//    @State private var urls: [URL] = []
//    @State private var currentRemote: DiscoveryViewModel.VMRemote? = nil
    
    var body: some View {
        NavigationView {
            VStack {
                RemoteListView(discoveryViewModel: .init(warp: warp))
            }
            
            .toolbar {
                ToolbarItem {
                    Button {
                        warp.resetupListener()
                    } label: {
                        Text("restart listener")
                    }
                }
                
                ToolbarItem {
                    Button {
                        warp.restart()
                    } label: {
                        Text("restart servers and bonjour")
                    }
                }

            }

            VStack {
                Text(":)")
            }
        }.onAppear {
            warp.start()
        }
        .toolbar {
            ToolbarItem(placement: .navigation){
                Button {
                    toggleSidebar()
                } label: {
                    Image(systemName: "sidebar.leading")
                }
            }
        }
    }
    
    private func toggleSidebar() {
        #if os(macOS)
        NSApp.keyWindow?.firstResponder?.tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
        #endif
    }
}





//struct ItemCard: View {
//
//    let title: String
//
//    var body: some View {
//     }
//}



struct RemoteListView: View {
    
    @ObservedObject var discoveryViewModel: DiscoveryViewModel
    
    var body: some View {
        List(discoveryViewModel.remotes) { remote in
            NavigationLink(destination: RemoteDetailView(viewModel: remote.getRemoteDetailVM()))
            {
                RemoteListViewItem(remote: remote)
            }
        }.frame(minWidth: 300)
    }
}

struct RemoteListViewItem: View {
    
    @ObservedObject var remote: DiscoveryViewModel.RemoteItem
    
    var body: some View {
        HStack {
            VStack (alignment: .leading) {
                HStack {
                    Image(systemName: remote.connectivityImageSystemName)
                    VStack (alignment: .leading) {
                        Text(remote.title)
                            .fontWeight(.bold)
                            .padding(5)
                        Text(remote.subTitle)
                            .padding(5)
                    }
                }.padding()
            }
             Spacer()
         }

    }
}
