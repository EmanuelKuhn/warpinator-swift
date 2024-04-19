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

#if os(macOS)
import AppKit
#endif

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    @State private var showingSettings = false
    
    var discoveryViewModel: DiscoveryViewModel {
        .init(remoteRegistration: appState.remoteRegistration)
    }
    
    var body: some View {
        navigationView
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
    
    var navigationView: some View {
        NavigationView {
            VStack {
                switch appState.state {
                case .notInitialized:
                    ProgressView("Initializing...")
                case .stopped:
                    ProgressView("Stopped...")
                case .restarting:
                    ProgressView("Restarting...")
                case .failure(let warpError):
                    VStack {
                        Text(warpError.localizedDescription)
                        Button("Try again") {
                            Task.detached {
                                await appState.warpManager.restart()
                            }
                        }
                    }.padding()
                case .unableToDiscoverSelf:
                    Text("Please enable local networking permission.")
                case .running:
                    RemoteListView(discoveryViewModel: discoveryViewModel)
                }
            }
            .toolbar {
#if !os(macOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingSettings = true
                    }) {
                        Image(systemName: "gear")
                    }
                }
#endif
                ToolbarItem {
                    Button {
                        Task.detached {
                            await appState.warpManager.resetupListener()
                        }
                    } label: {
                        Text("restart listener")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            
            VStack {
                Text(":)")
            }
        }
    }
    
    
    
    private func toggleSidebar() {
#if os(macOS)
        NSApp.keyWindow?.firstResponder?.tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
#endif
    }
}

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
                        Text(remote.resolvedHost)
                            .padding(5)
                    }
                }.padding()
            }
            Spacer()
        }
        
    }
}
