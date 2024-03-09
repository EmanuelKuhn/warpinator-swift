//
//  TransferOpView.swift
//  warpinator-project
//
//  Created by Emanuel on 24/05/2022.
//

import Foundation
import SwiftUI

import Combine

#if canImport(AppKit)
import AppKit
#endif

import UniformTypeIdentifiers

extension Direction {
    var imageSystemName: String {
        switch self {
        case .upload:
            return "arrow.up.to.line.alt"
        case .download:
            return "arrow.down.to.line.alt"
        }
    }
}

struct TransferOpView: View {

    @ObservedObject
    var viewModel: ViewModel

    var body: some View {
        HStack {
            Image(systemName: viewModel.directionImageSystemName)
            #if canImport(AppKit)
            Image(nsImage: NSWorkspace.shared.icon(for: viewModel.uttype))
            #endif

            Text(viewModel.title)
                .frame(maxWidth: 250, alignment: .leading)

            Text(viewModel.size).frame(maxWidth: 50, alignment: .leading)

            StatusView(state: viewModel.state, progress: viewModel.progressMetrics)

            Spacer()

            actionButtons

        }
    }
    
    var actionButtons: some View {
        switch(viewModel.availableActions) {
        case .acceptOrCancel:
            return AnyView(HStack {
                Button {
                    viewModel.accept()
                } label: {
                    Image(systemName: "checkmark")
                }.buttonStyle(.borderless)
                
                Button {
                    viewModel.cancel()
                } label: {
                    Image(systemName: "xmark")
                }.buttonStyle(.borderless)
            })

        case .cancel:
            return AnyView(
                Button {
                    viewModel.cancel()
                } label: {
                    Image(systemName: "xmark")
                }.buttonStyle(.borderless)
            )
        case .remove:
            return AnyView(
                Button {
                    viewModel.remove()
                } label: {
                    Image(systemName: "minus")
                }.buttonStyle(.borderless)
            )
        case .removeOrShow:
            return AnyView(HStack {
                Button {
                    viewModel.locate()
                } label: {
                    Image(systemName: "folder")
                }.buttonStyle(.borderless)

                Button {
                    viewModel.remove()
                } label: {
                    Image(systemName: "minus")
                }.buttonStyle(.borderless)

            })
        }
    }
}

struct StatusView: View {
    
    let state: TransferOpState
    
    @ObservedObject
    var progress: TransferOpMetrics
    
    var body: some View {
        Group {
            if state == .started {
                AnyView(ProgressView(value: Double(progress.bytesTransmittedCount),
                                     total: Double(progress.totalBytesCount)))
            } else {
                AnyView(Text(String(describing: state)))
            }
        }.frame(maxWidth: 250, alignment: .leading)
    }

}

extension TransferOpView {
    @MainActor
    class ViewModel: Identifiable, ObservableObject {

        private var transferOp: TransferOp

        var title: String {
            transferOp.title
        }
        
        var size: String {
            ByteCountFormatter.string(fromByteCount: Int64(transferOp.size), countStyle: .file)
        }
        
        var state: TransferOpState {
            transferOp.state
        }
        
        var stateDescription: String {
            String(describing: transferOp.state)
        }
        
        var progressMetrics: TransferOpMetrics {
            transferOp.progress
        }
        
        var directionImageSystemName: String {
            transferOp.direction.imageSystemName
        }
        
        var availableActions: TransferOpAvailableActions {
            transferOp.availableActions
        }
        
        var uttype: UTType {
            let defaultType: UTType = transferOp.count == 1 ? .data : .folder
            
            return UTType.init(mimeType: transferOp.mimeType) ?? defaultType
        }
        
        func accept() {
            
            guard let transferOp = transferOp as? TransferFromRemote else {
                preconditionFailure()
            }
            
            Task {
                try? await transferOp.accept()
            }
        }
        
        func cancel() {
            Task {
                await transferOp.cancel()
            }
        }
        
        func remove() {
            transferOp.remove()
        }
        
        func locate() {
            
            guard let transferOp = transferOp as? TransferFromRemote else {
                return
            }
            
            print("localurls:")
            print(transferOp.localSaveUrls)
            
            #if os(macOS)
            NSWorkspace.shared.activateFileViewerSelecting(transferOp.localSaveUrls)
            #endif
            
            //TODO: Show file location on iOS
            
        }

        var bag: Set<AnyCancellable> = .init()

        init(transferOp: TransferOp) {
            self.transferOp = transferOp

            transferOp._state.objectWillChange.receive(on: DispatchQueue.main).sink(receiveValue: {
                self.objectWillChange.send()
            }).store(in: &bag)
        }
    }
}
