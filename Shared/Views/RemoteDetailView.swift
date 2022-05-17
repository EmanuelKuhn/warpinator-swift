//
//  RemoteDetailView.swift
//  warpinator-project (macOS)
//
//  Created by Emanuel on 25/04/2022.
//

import Foundation
import SwiftUI

import Combine

struct RemoteDetailView: View {
    
    @ObservedObject
    var viewModel: ViewModel
    
    @State
    var urls: [URL] = []
    
    @State
    var showingSheet = false
    
    var body: some View {
        VStack {
            VStack {
                Text("Transfers: \(viewModel.transfers.count)").font(.title2)
                
                List(viewModel.transfers) { transfer in
                    TransferOpView(viewModel: transfer)
                }
                
                Spacer()
            }
        }.navigationTitle(viewModel.title)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Send files") {
                        showingSheet.toggle()
                    }
                }
                
                ToolbarItem(placement: .automatic) {
                    Button("Ping") {
                        viewModel.ping()
                    }
                }
            }
            .sheet(isPresented: $showingSheet) {
                if urls.count > 0 {
                    viewModel.sendFiles(urls: urls)
                }
            } content: {
                #if canImport(UIKIT)
                DocumentPicker(urls: $urls)
                #else
                Text("mac")
                #endif
            }

    }
}

extension Direction {
    var imageSystemName: String {
        switch self {
        case .upload:
            return "square.and.arrow.up"
        case .download:
            return "square.and.arrow.down"
        }
    }
}

struct TransferOpView: View {

    @ObservedObject
    var viewModel: ViewModel

    var body: some View {
        HStack {
            Image(systemName: viewModel.directionImageSystemName)
            Text(viewModel.title)
        }
    }
}

extension TransferOpView {
    class ViewModel: Identifiable, ObservableObject {
        
        private let transferOp: TransferOp
        
        let title: String
        
        let directionImageSystemName: String
        
        init(transferOp: TransferOp) {
            self.transferOp = transferOp
            
            directionImageSystemName = transferOp.direction.imageSystemName
            
            title = "Some transfer"
        }
    }
}

extension RemoteDetailView {
    class ViewModel: Identifiable, ObservableObject {
        
        let title: String
        
        @Published
        var transfers: Array<TransferOpView.ViewModel> = []
        
        private let remote: Remote
        
        private var token: AnyCancellable? = nil
        
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
            
            self.title = remote.peer.hostName
            
            token = remote.transfers.sink { transfers in
                let transferVMS: [TransferOpView.ViewModel] = transfers.map {
                    .init(transferOp: $0)
                }
                
                DispatchQueue.main.async {
                    self.transfers = transferVMS
                }
            }
            
        }
    }
}
