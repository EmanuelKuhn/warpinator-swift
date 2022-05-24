//
//  TransferOpView.swift
//  warpinator-project
//
//  Created by Emanuel on 24/05/2022.
//

import Foundation
import SwiftUI

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

