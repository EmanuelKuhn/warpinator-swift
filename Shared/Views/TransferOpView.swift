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

extension Direction {
    var imageSystemName: String {
        switch self {
        case .upload:
            return "chevron.up"
        case .download:
            return "chevron.down"
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
            Image(nsImage: NSWorkspace.shared.icon(for: (.init(filenameExtension: "pdf") ?? .data)))
            #endif

            Text(viewModel.title)
                .frame(maxWidth: 250, alignment: .leading)

            Text(viewModel.size).frame(maxWidth: 50, alignment: .leading)

            Text(String(describing: viewModel.state)).frame(maxWidth: 250, alignment: .leading)

            Spacer()

            actionButtons

        }
    }

    var actionButtons: some View {
        switch(viewModel.availableActions) {
        case .acceptOrCancel:
            return AnyView(HStack {
                Button {
                    viewModel.cancel()
                } label: {
                    Image(systemName: "xmark")
                }.buttonStyle(.borderless)

                Button {
                    viewModel.accept()
                } label: {
                    Image(systemName: "checkmark")
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
        }
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
        
        var state: String {
            String(describing: transferOp.state)
        }
        
        var directionImageSystemName: String {
            transferOp.direction.imageSystemName
        }
        
        var availableActions: TransferOpAvailableActions {
            transferOp.availableActions
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

        var bag: Set<AnyCancellable> = .init()

        init(transferOp: TransferOp) {
            self.transferOp = transferOp

            transferOp._state.objectWillChange.receive(on: DispatchQueue.main).sink(receiveValue: {
                self.objectWillChange.send()
            }).store(in: &bag)
        }
    }
}
