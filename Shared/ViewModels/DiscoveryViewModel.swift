//
//  DiscoveryViewModel.swift
//  warpinator-project
//
//  Created by Emanuel on 12/02/2022.
//

import Foundation

import Combine

extension RemoteState {
    var systemImageName: String {
        switch self {
        case .fetchingCertificate:
            return "wave.3.right" // 􀙲
        case .waitingForDuplex:
            return "dot.radiowaves.right" // 􀖒
        case .online:
            return "wifi" // 􀙇
        case .offline:
            return "wifi.slash" // 􀙈
        case .failure(let failure):
            return failure.systemImageName
        case .retrying:
            return "arrow.counterclockwise.circle" // 􀚃
        }
    }
}

extension Failure {
    var systemImageName: String {
        switch self {
        case .channelFailure:
            return "fiberchannel"
        case .remoteError(let remoteError):
            return remoteError.systemImageName
        }
    }
}

extension RemoteError {
    var systemImageName: String {
        switch self {
        case .failedToResolvePeer:
            return "wifi.exclamationmark" // 􀙥
        case .failedToUnlockCertificate:
            return "lock.slash" // 􀎢
        case .peerMissingFetchCertInfo, .failedToFetchLockedCertificate, .failedToPing, .failedToGetDuplex:
            return "display.trianglebadge.exclamationmark" // 􀨦
        case .failedToMakeWarpClient, .clientNotInitialized:
            return "questionmark.diamond" // 􀄢
        }
    }
}

@MainActor
class DiscoveryViewModel: ObservableObject {
    @MainActor
    class RemoteItem: Identifiable, ObservableObject {
        
        let id: String
        
        @Published
        var title: String
        
        @Published
        var subTitle: String
        
        private let remote: Remote
        
        @Published
        var connectivityImageSystemName: String = RemoteState.offline.systemImageName
        
        @Published
        var resolvedHost: String
        
        var tokens: Set<AnyCancellable> = .init()
        
        init(remote: Remote) {
            self.id = remote.id
            
            self.title = remote.peer.hostName
            
            self.subTitle = ""
            
            self.resolvedHost = ""
            
            
            self.remote = remote
            
            Task {
                tokens.update(with: remote.$state.receive(on: DispatchQueue.main).sink { newState in
                    self.connectivityImageSystemName = newState.systemImageName
                })
                
                tokens.update(with: remote.$remoteMachineInfo.receive(on: DispatchQueue.main).sink { newInfo in
                    self.title = newInfo?.displayName ?? remote.peer.hostName
                                        
                    if let username = newInfo?.userName {
                        self.subTitle = "\(username)@\(remote.peer.hostName)"
                    } else {
                        self.subTitle = remote.peer.hostName
                    }
                })
                
                tokens.update(with: remote.$resolved.receive(on: DispatchQueue.main).sink { newResolved in
                    self.resolvedHost = newResolved?.host ?? ""
                })

            }
        }

        
        func getRemoteDetailVM() -> RemoteDetailView.ViewModel {
            return .init(remote: remote)
        }
    }
    
    @Published var remotes: Array<RemoteItem> = []
    
    init(remoteRegistration: RemoteRegistrationObserver) {
        Task {
            await remoteRegistration.addOnRemoteChangedListener { remotes in
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
