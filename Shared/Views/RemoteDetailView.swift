//
//  RemoteDetailView.swift
//  warpinator-project (macOS)
//
//  Created by Emanuel on 25/04/2022.
//

import Foundation
import SwiftUI

import Combine

#if canImport(AppKit)
import AppKit
#endif

struct RemoteDetailView: View {
    
    @ObservedObject
    var viewModel: ViewModel
        
    @State
    var showingSheet = false
    
    var body: some View {
        VStack {
            VStack {
                
                List {
                    Section(content: {
                        ForEach(viewModel.transfers) { transfer in
                            TransferOpView(viewModel: transfer)
                            #if os(macOS)
                            Divider()
                            #endif
                            }
                    }, header: {
                        Text("Transfers")
                    })
                }.overlay(Group {
                    if viewModel.transfers.isEmpty {
                        Text("No transfers yet...")
                    }
                })
            }
        }.navigationTitle("\(viewModel.title) (\(viewModel.state))")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Send files") {
                        #if os(macOS)
                        openFilesMac(onPick: sendFiles)
                        #else
                        showingSheet.toggle()
                        #endif
                    }
                }
            }
            #if !os(macOS)
            .sheet(isPresented: $showingSheet, content: {
                DocumentPicker(onPick: sendFiles)
            })
            #endif
    }
    
    func sendFiles(urls: [URL]) {
        if urls.count > 0 {
            viewModel.sendFiles(urls: urls)
        }
    }
    
    #if canImport(AppKit)
    func openFilesMac(onPick: @escaping ([URL])->()) {
        let openPanel = NSOpenPanel()
        openPanel.prompt = "Select Files"
        openPanel.allowsMultipleSelection = true
        openPanel.canChooseDirectories = false
        openPanel.canCreateDirectories = false
        openPanel.canChooseFiles = true
        
        openPanel.begin { (result) -> Void in
            if result.rawValue == NSApplication.ModalResponse.OK.rawValue {
                onPick(openPanel.urls)
            }
        }
    }
    #endif

}


extension RemoteState {
    var description: String {
        switch self {
        case .fetchingCertificate:
            return "connecting"
        case .offline:
            return "offline"
        case .waitingForDuplex:
            return "waiting for duplex"
        case .online:
            return "online"
        case .retrying:
            return "retrying"
        case .failure(let failure):
            return failure.description
        }
    }
}

extension Failure {
    var description: String {
        switch self {
        case .remoteError(let remoteError):
            return remoteError.localizedDescription
        case .channelFailure:
            return "channel failure"
        }
    }
}

extension RemoteError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .failedToResolvePeer:
            return "Failed to resolve"
        case .failedToFetchLockedCertificate:
            return "Failed to fetch certificate"
        case .failedToMakeWarpClient:
            return "Failed to connect"
        case .failedToPing:
            return "Ping request failed"
        case .failedToUnlockCertificate:
            return "Incorrect groupcode"
        case .failedToGetDuplex:
            return "Failed to get duplex"
        case .clientNotInitialized:
            return "Client not initialized"
        case .peerMissingFetchCertInfo:
            return "peerMissingFetchCertInfo"
        }
    }
}


extension RemoteDetailView {
    @MainActor
    class ViewModel: Identifiable, ObservableObject {
        
        let title: String
        
        @Published
        var transfers: Array<TransferOpView.ViewModel> = []
        
        @Published
        var state: String = ""
        
        private let remote: Remote
        
        private var tokens: Set<AnyCancellable> = .init()
        
        func sendFiles(urls: [URL]) {
            Task {
                try? await remote.requestTransfer(url: urls[0])
            }
        }
        
        func ping() {
            Task {
                try? await remote.ping()
            }
        }
        
        init(remote: Remote) {
            self.remote = remote
            
            self.title = remote.peer.hostName
            
            remote.transfers.sink { transfers in
                let transferVMS: [TransferOpView.ViewModel] = transfers.map {
                    .init(transferOp: $0)
                }
                
                DispatchQueue.main.async {
                    self.transfers = transferVMS
                }
            }.store(in: &tokens)
            
            Task {
                remote.$state.receive(on: DispatchQueue.main).sink { state in
                    self.state = "\(state.description)"
                }.store(in: &tokens)
            }
            
        }
    }
}
