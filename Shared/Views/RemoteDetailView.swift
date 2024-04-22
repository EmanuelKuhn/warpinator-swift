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

class LayoutInfo: ObservableObject {
    @Published var width: CGFloat = 0
}

struct RemoteDetailView: View {
    
    @ObservedObject
    var viewModel: ViewModel
        
    @State
    var showingSheet: Bool
    
    @StateObject
    var layoutInfo = LayoutInfo()
    
    init(viewModel: ViewModel, showingSheet: Bool=false) {
        self.viewModel = viewModel
        self.showingSheet = showingSheet
        
#if canImport(UIKit)
        // On iOS the title tends to get truncated.
        // This sets a property of the underlying UILabel to  adjust the font size to fit.
        UILabel.appearance(whenContainedInInstancesOf: [UINavigationBar.self]).adjustsFontSizeToFitWidth = true
#endif
    }
    
    var body: some View {
        GeometryReader {geom in
            VStack(spacing: 0) {
                if viewModel.showStatusView {
                    statusView
                        .frame(height: 30, alignment: .center)
                        .padding(.vertical, 10)
                }
                
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
            }.onAppear() {
                layoutInfo.width = geom.size.width
            }.onChange(of: geom.size) { newSize in
                layoutInfo.width = newSize.width
            }
            .navigationTitle(Text(viewModel.title))
            
#if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
#endif
            
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
        }.environmentObject(layoutInfo)
    }
    
    @ViewBuilder
    var statusView: some View {
        HStack(spacing: 8) {
            Image(systemName: viewModel.state.systemImageName) // Example system icon
                .foregroundColor(.secondary)
            Text(viewModel.stateDescription)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
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
        var stateDescription: String = ""
        
        @Published
        var state: RemoteState = .offline
        
        @Published
        var showStatusView: Bool = true
        
        private let remote: RemoteProtocol
        
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
        
        init(remote: RemoteProtocol) {
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
                remote.statePublisher().receive(on: DispatchQueue.main).sink { state in
                    self.stateDescription = state.description
                    self.state = state
                    
                    withAnimation {
                        self.showStatusView = self.state != .online
                    }
                }.store(in: &tokens)
            }
        }
    }
}


#if DEBUG

class DummyRemote: RemoteProtocol {
    var peer: Peer = MDNSPeer(domain: "mint.local", type: "real", name: "Warpinator mint", txtRecord: .init())
    
    var transfers: CurrentValueSubject<Array<TransferOp>, Never> = .init([DummyTransferOp(), DummyTransferOp.multiTransfer, DummyTransferOp()])
    
    var state: RemoteState = .online
    
    func ping() async throws {
        
    }
    
    func requestTransfer(url: URL) async throws {
        
    }
    
    func statePublisher() -> AnyPublisher<RemoteState, Never> {
        CurrentValueSubject<RemoteState, Never>.init(.online).eraseToAnyPublisher()
    }
    
    
}

extension RemoteDetailView.ViewModel {
    static var preview: Self {
        let dummyRemote = DummyRemote()
        
        return RemoteDetailView.ViewModel(remote: dummyRemote) as! Self
    }
}

struct RemoteDetailViewPreview: PreviewProvider {
    static var previews: some View {
        RemoteDetailView(viewModel: RemoteDetailView.ViewModel.preview, showingSheet: false)
    }
}


#endif
