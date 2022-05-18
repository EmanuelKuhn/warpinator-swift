//
//  DiscoveryViewModel.swift
//  warpinator-project
//
//  Created by Emanuel on 12/02/2022.
//

import Foundation


extension RemoteState {
    var systemImageName: String {
        switch self {
        case .mdnsDiscovered:
            return "wave.3.right"
        case .waitingForDuplex:
            return "dot.radiowaves.right"
        case .online:
            return "wifi"
        case .mdnsOffline:
            return "wifi.slash"
        case .failure:
            return "wifi.exclamationmark"
        }
    }
}

@MainActor
class DiscoveryViewModel: ObservableObject {

    class RemoteItem: Identifiable, ObservableObject {
        
        let id: String
        
        let title: String
        
        private let remote: Remote
        
        @Published
        var connectivityImageSystemName: String = RemoteState.mdnsOffline.systemImageName
        
        var token: Any? = nil
        
        init(remote: Remote) {
            self.id = remote.id
            self.title = remote.peer?.hostName ?? "hostname"
            
            self.remote = remote
            
            Task {
                token = await remote.statePublisher.sink { newState in
                    DispatchQueue.main.async {
                        self.connectivityImageSystemName = newState.systemImageName
                    }
                }
            }
        }

        
        func getRemoteDetailVM() -> RemoteDetailView.ViewModel {
            return .init(remote: remote)
        }
    }
    
    @Published var remotes: Array<RemoteItem> = []
    
    init(warp: WarpBackend) {
        Task {
            await warp.remoteRegistration.addOnRemoteChangedListener { remotes in
                print("DiscoveryViewModel: onRemotesChangedListener")
                
                self.setRemotes(remotes: remotes)
            }
        }
    }
    
    private func setRemotes(remotes: Array<Remote>) {
        
        let remoteItems = remotes.map({ remote in
            RemoteItem(remote: remote)
        })
        
        DispatchQueue.main.async {
            self.remotes = remoteItems
        }
    }
    
}
