//
//  DocumentPicker.swift
//  warpinator-project
//
//  Created by Emanuel on 23/03/2022.
//

import SwiftUI

#if canImport(UIKit)

import UIKit

struct DocumentPicker: UIViewControllerRepresentable {
    
    let onPick: ([URL]) -> Void
    
    typealias UIViewControllerType = UIDocumentPickerViewController
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let viewController: UIDocumentPickerViewController = .init(forOpeningContentTypes: [.item])
        
        viewController.allowsMultipleSelection = true
        
        viewController.delegate = context.coordinator
        
        return viewController
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {
        print("updateUIViewController()", context)
    }
    
    func makeCoordinator() -> Coordinator {
        print("makeCoordinator()")
        
        return Coordinator(parent: self)
    }
    
    internal class Coordinator: NSObject, UIDocumentPickerDelegate {
        
        let parent: DocumentPicker
        
        init(parent: DocumentPicker) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            print("documentPicker, did pick: \(urls)")
            
            parent.onPick(urls)
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            print("documentPickerWasCancelled")
        }
    }
    
}

#endif
