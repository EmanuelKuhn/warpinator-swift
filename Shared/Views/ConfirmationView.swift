//
//  ConfirmationView.swift
//  warpinator-project
//
//  Created by Emanuel on 10/03/2024.
//

import SwiftUI

struct ConfirmDestructiveActionModifier: ViewModifier {
    @Binding var isPresented: Bool
    
    let title: String
    //    let message: String
    
    let confirmText = "Overwrite"
    let cancelText = "Cancel"
    
    let onConfirm: () -> Void
    let onCancel: (() -> Void)?
    
    
    func body(content: Content) -> some View {
#if os(macOS)
        content.popover(isPresented: $isPresented) {
            popoverView
        }
#else
        content.actionSheet(isPresented: $isPresented) {
            actionSheet
        }
#endif
    }
    
#if os(macOS)
    var popoverView: some View {
        VStack {
            Text(title)
            
            HStack {
                Button(cancelText) {
                    self.isPresented = false
                    if let onCancel = self.onCancel {
                        onCancel()
                    }
                }
                Button(confirmText) {
                    self.isPresented = false
                    self.onConfirm()
                }
            }
        }.padding()
    }
#else
    var actionSheet: ActionSheet {
        ActionSheet(title: Text(title), message: nil, buttons: [
            .cancel(Text(cancelText), action: onCancel),
            .destructive(Text(confirmText), action: onConfirm)
        ])
    }
#endif
    
}

extension View {
    func overwriteConfirmation(isPresented: Binding<Bool>, title: String, onConfirm: @escaping () -> Void, onCancel: (() -> Void)?=nil) -> some View {
        self.modifier(ConfirmDestructiveActionModifier(
            isPresented: isPresented, title: title, onConfirm: onConfirm, onCancel: onCancel)
        )
    }
}
