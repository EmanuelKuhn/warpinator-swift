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

    @EnvironmentObject
    var layoutInfo: LayoutInfo
    
    var body: some View {
        if layoutInfo.width < 500 {
            narrowView
        } else {
            wideView
        }
    }
    
    var wideView: some View {
        HStack {
            Image(systemName: viewModel.directionImageSystemName).frame(width: 20, alignment: .center)
            
            Image(systemName: viewModel.fileIconSystemName).frame(width: 20, alignment: .center)
            
            Text(viewModel.title).lineLimit(1).truncationMode(.middle)
                .frame(minWidth: 200, alignment: .leading)

            Text(viewModel.size).frame(minWidth: 80, alignment: .leading)

            StatusView(state: viewModel.state, progress: viewModel.progressMetrics)
                .frame(width: 85)

            Spacer()

            actionButtons

        }
        #if !os(macOS)
        .frame(minHeight: 40)
        #endif
    }
    
    var narrowView: some View {
        HStack {
            HStack {
                Image(systemName: viewModel.directionImageSystemName)
                
                Image(systemName: viewModel.fileIconSystemName)
            }
            
            VStack {
                HStack {
                    Text(viewModel.title).bold().lineLimit(1).truncationMode(.middle)
                    
                    Spacer()
                }.padding(.bottom, 2.0).frame(alignment: .leading)
                
                HStack {
                    Text(viewModel.size).frame(minWidth: 40, alignment: .leading)
                    
                    StatusView(state: viewModel.state, progress: viewModel.progressMetrics).frame(alignment: .center)
                    
                    Spacer()
                }
            }
            .padding()
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
        
        var fileIconSystemName: String {
            /** System icon name to represent the file transfer */
            
            if transferOp.count == 1 {
                
                print("UTType: \(self.uttype)")
                
                if self.uttype.conforms(to: .image) {
                    return "photo"
                } else if self.uttype.conforms(to: .archive) {
                    return "doc.zipper"
                } else if self.uttype.conforms(to: .plainText) {
                    return "doc.plaintext"
                } else if self.uttype.conforms(to: .text) {
                    return "doc.text"
                } else if self.uttype.conforms(to: .content) {
                    return "doc.fill"
                } else {
                    return "doc"
                }
            } else {
                if transferOp.mimeType.contains("directory") {
                    return "folder"
                } else {
                    return "doc.on.doc"
                }
            }
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

#if DEBUG

class DummyTransferOp: TransferOp {
    var direction: Direction = .download
    
    var localTimestamp: Date = .init()
    
    var timestamp: UInt64 = DispatchTime.now().rawValue
    
    var _state: MutableObservableValue<TransferOpState> = .init(.requested)
    
    var title: String = "warpinator-project.app.dSYM.zip"
    
    var mimeType: String = "archive/zip"
    
    var size: UInt64 = 1002
    
    var count: UInt64 = 1
    
    var topDirBasenames: [String] = ["image.png"]
    
    func cancel() async {
        
    }
    
    func remove() {
        
    }
    
    var progress: TransferOpMetrics = .init(totalBytesCount: 1000)
    
    
}

extension TransferOpView.ViewModel {
    static var preview: Self {
        let dummyTransferOp = DummyTransferOp()
        
        return TransferOpView.ViewModel(transferOp: dummyTransferOp) as! Self
    }
}

struct TransferOpView_Previews: PreviewProvider {
    static var previews: some View {
        TransferOpView(viewModel: TransferOpView.ViewModel.preview).environmentObject(LayoutInfo())
    }
}


#endif
