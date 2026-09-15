//
//  SettingsView.swift
//  warpinator-project
//
//  Created by Emanuel on 19/03/2023.
//

import SwiftUI

#if os(macOS)
import AppKit
#endif

struct SettingsView: View {
    
    @ObservedObject
    var settings: WarpSetingsUserDefaults

    @ObservedObject
    var downloadFolder: DownloadFolder

    @State var portText: String = ""
    @State var authPortText: String = ""

    @State var groupCodeText: String = ""
    
    init() {
        settings = .shared
        downloadFolder = .shared
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

            Section(header: Text("Download folder")) {
                LabeledHStack("Save to") {
                    Text(downloadFolder.displayPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(downloadFolder.displayPath)
                }

                HStack {
                    Button("Choose...", action: chooseDownloadFolder)

                    Button("Use default", action: { downloadFolder.reset() })
                        .disabled(!downloadFolder.isCustom)
                }
            }

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

#if os(macOS)
    /// Ask the user for a folder. Picking it through NSOpenPanel is what grants the
    /// sandboxed app access to it, which is then persisted as a security scoped bookmark.
    private func chooseDownloadFolder() {
        let panel = NSOpenPanel()

        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose the folder received files are saved to"
        panel.directoryURL = downloadFolder.url

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            try downloadFolder.select(url: url)
        } catch {
            print("Failed to select download folder: \(error)")
        }
    }
#endif
}

// Preview Provider
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
