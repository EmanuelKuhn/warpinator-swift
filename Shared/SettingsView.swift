//
//  SettingsView.swift
//  warpinator-project
//
//  Created by Emanuel on 19/03/2023.
//

import SwiftUI

struct SettingsView: View {
    
    var settings: WarpSetingsUserDefaults
        
    @State var portText: String
    @State var authPortText: String

    @State var groupCodeText: String
    
    init() {
        settings = .shared
        
        portText = String(settings.port)
        authPortText = String(settings.authPort)
        
        groupCodeText = String(settings.groupCode)
    }
    
    var body: some View {
        Form {
            
            Section(header: Text("Group code")) {
                LabeledHStack("Group code") {
                    TextField("Group Code", text: $groupCodeText)
                }
                                                
                Button("Set code", action: {
                    settings.groupCode = groupCodeText
                })
            }

        }
        .padding(20)
        .frame(width: 350)
    }
}


