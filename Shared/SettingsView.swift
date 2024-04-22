//
//  SettingsView.swift
//  warpinator-project
//
//  Created by Emanuel on 19/03/2023.
//

import SwiftUI

struct SettingsView: View {
    
    @ObservedObject
    var settings: WarpSetingsUserDefaults
        
    @State var portText: String = ""
    @State var authPortText: String = ""

    @State var groupCodeText: String = ""
    
    init() {
        settings = .shared
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
            
#if os(macOS)
            Divider()
                .padding(.vertical, 5.0)
#endif
            
            Section(header: Text("Network ports")) {
                LabeledHStack("Port") {
                    TextField("Port", text: $portText)
                }
                
                LabeledHStack("Auth port") {
                    TextField("Auth port", text: $authPortText)
                }
                
                Button("Set ports", action: {
                    guard let port = Int(portText) else { return }
                    guard let authPort = Int(authPortText) else { return }
                    
                    settings.port = port
                    settings.authPort = authPort
                })
            }
            
#if os(macOS)
            Divider()
                .padding(.vertical, 5.0)
#endif

            Section(header: Text("Debug settings")) {
                Toggle("Allow connecting to self", isOn: .init(get: {
                    settings.canDiscoverSelf
                }, set: { canDiscoverSelf in
                    settings.canDiscoverSelf = canDiscoverSelf
                }))
            }
        }
        .onAppear {
            portText = String(settings.port)
            authPortText = String(settings.authPort)
            
            groupCodeText = String(settings.groupCode)
        }
    }
}

// Preview Provider
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
