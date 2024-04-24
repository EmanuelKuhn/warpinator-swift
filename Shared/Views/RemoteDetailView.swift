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

import UniformTypeIdentifiers

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
    
    @State
    var isDropTargeted: Bool = false
    
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
                .overlay(isDropTargeted ? Color.primary.opacity(0.4).blendMode(.hardLight) : nil)
                .onDrop(of: [.fileURL], delegate: MyDropDelegate(isTargeted: $isDropTargeted, isActive: !viewModel.disableSendFileButton, callback: { urls in
                    sendFiles(urls: urls)
                }))
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
                        .disabled(viewModel.disableSendFileButton)
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

struct MyDropDelegate: DropDelegate {
        
    let isTargeted: Binding<Bool>?
    
    let isActive: Bool?
    
    let callback: ([URL]) -> ()
        
    func validateDrop(info: DropInfo) -> Bool {
        return info.hasItemsConforming(to: [.fileURL])
    }
    
    func dropEntered(info: DropInfo) {
        self.isTargeted?.wrappedValue = validateDrop(info: info)
        
        print("self.isTargeted?.wrappedValue: \(self.isTargeted?.wrappedValue)")
    }
    
    func dropExited(info: DropInfo) {
        self.isTargeted?.wrappedValue = false
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard let isActive = isActive else {
            return nil
        }
        
        if isActive {
            return .init(operation: .copy)
        } else {
            return .init(operation: .forbidden)
        }

    }
    
    func performDrop(info: DropInfo) -> Bool {
        // Check that there are file urls
        guard info.hasItemsConforming(to: [.fileURL]) else { return false }
        
        let providers = info.itemProviders(for: [.fileURL])
                
        for provider in providers {
            
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (item, error) in
                
                if let error = error as NSError? {
                    print("performDrop Error: \(error)")
                }
                
                // The item that was dropped is Data...
                if let data = item as? Data {
                    
                    // Which can be decoded as a string
                    if let urlString = String(data: data, encoding: .utf8) {
                        // print("urlString: \(urlString)")
                        // For example "file:///.file/id=6571367.8720033194"
                        
                        // Attempt to create a URL from the string
                        if let url = URL(string: urlString) {
                            
                            print("url: \(url)")
#if os(macOS)

                            // Now the url is a normal looking URL to a path
                            do {
                                // Apparently the URL is only valid for a short time after the drop.
                                // To access it longer make a bookmark
                                let bookmarkData = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: [.isDirectoryKey, .fileSizeKey])

                                var stale = false
                                if let resolvedURL = try? URL(resolvingBookmarkData: bookmarkData, options: [.withSecurityScope], bookmarkDataIsStale: &stale) {
                                    
                                    // print("resolvedURL: \(resolvedURL)")
                                    // This resolvedURL is the same as url, but now the url can be accessed longer:
                                    assert(resolvedURL == url)
                                    
                                    Task {
                                        self.callback([resolvedURL])
                                    }
                                    
                                    // Here is should be possible to read from the file:
                                    // let fileContents = try String(contentsOf: url, encoding: .utf8)
                                    // print("File contents: \(fileContents)")
                                    
                                    if stale {
                                        print("Warning: for some reason the bookmark is stale")
                                    }
                                }
                            } catch {
                                print("Failed to make bookmarkData from URL: \(error)")
                            }
#endif
                        } else {
                            print("Invalid URL string.")
                        }
                    } else {
                        print("Data could not be decoded into a string.")
                    }
                } else {
                    print("Item is not of type Data.")
                }
            }
        }
        return true
    }
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
        
        @Published
        var disableSendFileButton: Bool = true
        
        private let remote: RemoteProtocol
        
        private var tokens: Set<AnyCancellable> = .init()
        
        func sendFiles(urls: [URL]) {
            Task {
                try? await remote.requestTransfer(urls: urls)
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
                    
                    self.disableSendFileButton = state != .online
                                        
                    // If the new status is online, delay hiding the view for 1 second
                    let willBecomeHidden = self.showStatusView && state == .online
                    let delayIfHiding = willBecomeHidden ? 1.0 : 0.0

                    withAnimation(.default.delay(delayIfHiding)) {
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
    
    func requestTransfer(urls: [URL]) async throws {
        
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
