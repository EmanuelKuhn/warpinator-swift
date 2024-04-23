//
//  TransferOpView.swift
//  warpinator-project
//
//  Created by Emanuel on 24/05/2022.
//

import Foundation
import SwiftUI

import Combine

import UniformTypeIdentifiers

extension String: Identifiable {
    public typealias ID = Int
    public var id: Int {
        return hash
    }
}

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
    
    @State
    var showConfirmPopover = false
    
    @State
    var isExpanded = false
    
    init(viewModel: ViewModel, isExpanded: Bool=false) {
        self.viewModel = viewModel
        self.isExpanded = isExpanded
    }
    
    var showNarrowView: Bool {
        layoutInfo.width < 500
    }
    
    var body: some View {
        if showNarrowView {
            narrowView
        } else {
            wideView
        }
    }
    
    var wideView: some View {
        VStack {
            HStack {
                Image(systemName: viewModel.directionImageSystemName).frame(width: 20, alignment: .center)
                
                Image(systemName: viewModel.fileIconSystemName).frame(width: 20, alignment: .center)
                
                VStack(alignment: .leading) {
                    HStack {
                        Text(viewModel.title).lineLimit(1).truncationMode(.middle)
                        if viewModel.showExpandButton {
                            expandButton
                        }
                    }
                    expandedTopDirNames
                }.frame(minWidth: 200, alignment: .leading).padding(.trailing, 10).padding(.leading, 2)
                
                
                
                Text(viewModel.size).frame(minWidth: 80, alignment: .leading)
                
                StatusView(state: viewModel.state, progress: viewModel.progressMetrics)
                    .frame(width: 85)
                
                Spacer()
                
                actionButtons
            }
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
                VStack(alignment: .leading) {
                    HStack {
                        Text(viewModel.title)
                            .bold().lineLimit(1).truncationMode(.middle)
                        if viewModel.showExpandButton {
                            expandButton
                        }
                        
                        Spacer()
                    }
                    
                    expandedTopDirNames
                }
                .padding(.bottom, 2.0).frame(alignment: .leading)
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
    
    var expandButton: some View {
        Button(action: {
            isExpanded.toggle()
        }) {
            Image(systemName: "chevron.right.circle")
                .rotationEffect(.degrees(self.isExpanded ? 90 : 0))
                .frame(alignment: .center)
        }.buttonStyle(.borderless)
    }
    
    var expandedTopDirNames: some View {
        VStack(alignment: .leading) {
            if self.isExpanded {
                VStack(alignment: .leading) {
                    ForEach(Array(viewModel.topDirBaseNames)) {name in
                        Text(name).lineLimit(1).truncationMode(.middle)
                    }
                }.frame(alignment: .leading)
                    .padding(.bottom, 3.0).padding(.top, 0.5)
                    .opacity(0.7)
            }
        }
    }
    
    var actionButtons: some View {
        switch(viewModel.availableActions) {
        case .acceptOrCancel:
            return AnyView(HStack {
                Button {
                    if viewModel.checkIfWillOverwrite() {
                        self.showConfirmPopover = true
                    } else {
                        viewModel.accept()
                    }
                } label: {
                    Image(systemName: "checkmark")
                }.buttonStyle(.borderless)
                    .overwriteConfirmation(
                        isPresented: $showConfirmPopover,
                        title: "Accepting this transfer will overwrite files. Are you sure?",
                        onConfirm: {
                            viewModel.accept()
                        }
                    )
                
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
        
        var topDirBaseNames: [String] {
            transferOp.topDirBasenames
        }
        
        var showExpandButton: Bool {
            if topDirBaseNames.count > 1 {
                return true
            }
            
            guard let topDirBaseName = topDirBaseNames.first else {
                // Transfer does not have files
                return false
            }
            
            // Show which file will be sent if the title doesn't match it
            // This is the case for e.g. a folder
            return topDirBaseName != self.title
        }
        
        func checkIfWillOverwrite() -> Bool {
            guard let transferOp = transferOp as? TransferOpFromRemote else {
                assertionFailure()
                return false
            }
            
            return transferOp.checkIfWillOverwrite()
        }
        
        func accept() {
            
            guard let transferOp = transferOp as? TransferOpFromRemote else {
                assertionFailure()
                return
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
            
            openFilesApp(urls: transferOp.localSaveUrls)
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

class DummyTransferOp: TransferOpFromRemote {
    func tryEvent(event: TransferOpEvent) {
        
    }
    
    func checkIfWillOverwrite() -> Bool {
        willOverwrite
    }
    
    func accept() async throws {
        
    }
    
    var direction: Direction = .download
    
    var localTimestamp: Date = .init()
    
    var timestamp: UInt64 = DispatchTime.now().rawValue
    
    var _state: MutableObservableValue<TransferOpState> = .init(.requested)
    
    var title: String = "warpinator-project.app.dSYM.zip"
    
    var mimeType: String = "archive/zip"
    
    var size: UInt64 = 1002
    
    var count: UInt64 = 1
    
    var topDirBasenames: [String] = ["image.png"]
    
    var willOverwrite: Bool = true
    
    init(direction: Direction = .download, title: String="warpinator-project.app.dSYM.zip", mimeType: String="archive/zip", size:UInt64=1430000, count: UInt64=1, topDirBaseNames: [String] = ["warpinator-project.app.dSYM.zip"], willOverwrite: Bool = true) {
        self.direction = direction
        self.title = title
        self.mimeType = mimeType
        self.size = size
        self.count = count
        self.topDirBasenames = topDirBaseNames
        
        self.willOverwrite = true
    }
    
    static var multiTransfer: DummyTransferOp = .init(title: "3 files", mimeType: "application/data", count: 3, topDirBaseNames: ["image.png", "archive.zip", "warpinator-project.app.dSYM.zip"])
    
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
        Group {
            TransferOpView(viewModel: TransferOpView.ViewModel.preview, isExpanded: false).environmentObject(LayoutInfo())
            TransferOpView(viewModel: TransferOpView.ViewModel.preview, isExpanded: true).previewLayout(.fixed(width: /*@START_MENU_TOKEN@*/199.0/*@END_MENU_TOKEN@*/, height: /*@START_MENU_TOKEN@*/100.0/*@END_MENU_TOKEN@*/)).environmentObject(LayoutInfo())
        }
    }
}


#endif
