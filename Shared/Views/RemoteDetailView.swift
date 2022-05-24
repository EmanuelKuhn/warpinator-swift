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
                        #if canImport(UIKIT)
                        showingSheet.toggle()
                        #else
                        openFilesMac(onPick: sendFiles)
                        #endif
                    }
                }
                
                ToolbarItem(placement: .automatic) {
                    Button("Ping") {
                        viewModel.ping()
                    }
                }
            }
            #if canImport(UIKIT)
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



extension RemoteDetailView {
    class ViewModel: Identifiable, ObservableObject {
        
        let title: String
        
        @Published
        var transfers: Array<TransferOpView.ViewModel> = []
        
        @Published
        var state: String = ""
        
        private let remote: Remote
        
        private var tokens: [AnyCancellable] = []
        
        func sendFiles(urls: [URL]) {
            Task {
                try? await remote.requestTransfer(url: urls[0])
            }
        }
        
        func ping() {
            Task {
                await remote.ping()
            }
        }
        
        init(remote: Remote) {
            self.remote = remote
            
            self.title = remote.peer?.hostName ?? "hostname"
            
            tokens.append(remote.transfers.sink { transfers in
                let transferVMS: [TransferOpView.ViewModel] = transfers.map {
                    .init(transferOp: $0)
                }
                
                DispatchQueue.main.async {
                    self.transfers = transferVMS
                }
            })
            
            Task {
                tokens.append(await remote.statePublisher.sink { state in
                    DispatchQueue.main.async {
                        self.state = "\(state)"
                    }
                })
            }
            
        }
    }
}
