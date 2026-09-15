//
//  Settings.swift
//  warpinator-project
//
//  Created by Emanuel on 19/03/2023.
//

import Foundation
import Combine
import SwiftProtobuf
import Accelerate

protocol WarpSettings {

    var identity: String { get }
    
    var port: Int { get }
    var authPort: Int { get }
    
    var groupCode: String { get }
    
    var canDiscoverSelf: Bool { get }
    
    func addOnConnectionSettingsChangedCallback(_: @escaping () -> Void)
}

enum WarpSettingsKey: String {
    case port, authPort, groupcode, canDiscoverSelf, downloadFolderBookmark
}

extension WarpSettingsKey {
    func get<T>(defaultValue: T) -> T {
        if let value = UserDefaults.standard.object(forKey: rawValue) as? T {
            return value
        }
        
        return defaultValue
    }
    
    func set<T>(newValue: T) {
        UserDefaults.standard.set(newValue, forKey: rawValue)
    }
}

class WarpSetingsUserDefaults: WarpSettings, ObservableObject {
    private static let defaultPort = 42000
    private static let defaultAuthPort = 42001
    
    static var shared = WarpSetingsUserDefaults()
    
    var connectionSettingsChangedCallbacks: [() -> ()] = []
    
    func addOnConnectionSettingsChangedCallback(_ callback: @escaping () -> Void) {
        connectionSettingsChangedCallbacks.append(callback)
    }

    
    var identity: String {
        return WarpSetingsUserDefaults.getIdentity(hostName: NetworkConfig.shared.hostname)
    }
    
    var port: Int {
        get { return WarpSettingsKey.port.get(defaultValue: WarpSetingsUserDefaults.defaultPort) }
        set {
            objectWillChange.send()
            
            WarpSettingsKey.port.set(newValue: newValue)
            
            signalConnectionSettingsChanged()
        }
    }
    
    var authPort: Int {
        get { return WarpSettingsKey.authPort.get(defaultValue: WarpSetingsUserDefaults.defaultAuthPort) }
        set {
            objectWillChange.send()
            
            WarpSettingsKey.authPort.set(newValue: newValue)
            
            signalConnectionSettingsChanged()
        }
    }
    
    var groupCode: String {
        get { return WarpSettingsKey.groupcode.get(defaultValue: DEFAULT_GROUP_CODE) }
        set {
            objectWillChange.send()
            
            WarpSettingsKey.groupcode.set(newValue: newValue)
            
            signalConnectionSettingsChanged()
        }
    }
    
    var canDiscoverSelf: Bool {
        get { return WarpSettingsKey.canDiscoverSelf.get(defaultValue: false) }
        set {
            objectWillChange.send()
            
            WarpSettingsKey.canDiscoverSelf.set(newValue: newValue)
            
            signalConnectionSettingsChanged()
        }
    }

    private func signalConnectionSettingsChanged() {
        DispatchQueue.global().async {
            self.connectionSettingsChangedCallbacks.forEach { $0() }
        }
    }
    
    
    static func getIdentity(hostName: String) -> String {
        
        let key = "identity"
        
        if UserDefaults.standard.string(forKey: key) == nil {
            let newIdentity = Auth.computeIdentity(hostName: hostName)
            UserDefaults.standard.set(newIdentity, forKey: key)
        }
        
        return UserDefaults.standard.string(forKey: key)!
    }
}


enum DownloadFolderError: Error {
    case notADirectory
}

extension DownloadFolderError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notADirectory:
            return "The selected path is not a folder"
        }
    }
}

/// The folder received files are written to.
///
/// By default files go to the app's own Documents directory. The app is sandboxed, so
/// any other folder is only reachable through a security scoped bookmark: the user
/// picks a folder once, the bookmark is persisted, and access is re-established on the
/// next launch. The resolved security scope is kept open for as long as the folder
/// stays selected, because transfers write to it at arbitrary moments.
class DownloadFolder: ObservableObject {

    static let shared = DownloadFolder()

    private let key = WarpSettingsKey.downloadFolderBookmark.rawValue

    /// The selected folder, or nil when the app's own Documents directory is used.
    ///
    /// Deliberately not @Published: the singleton is created lazily and the first access
    /// can happen on a background thread while a transfer is running, which would publish
    /// a change from off the main thread. The two mutating methods below are only reachable
    /// from the settings UI, so they signal the change themselves.
    private(set) var url: URL? = nil

    /// Holds the security scoped resource open while the folder stays selected.
    private var access: SecurityScopedURL? = nil

    private init() {
        self.url = restoreFromBookmark()
    }

    /// The folder a transfer should be written to.
    func resolve() throws -> URL {
        return try url ?? getDocumentsDirectory()
    }

    /// Whether a folder other than the default one is selected.
    var isCustom: Bool {
        return url != nil
    }

    /// The path to show in the settings UI.
    var displayPath: String {
        if let url = url {
            return url.path
        }

        return (try? getDocumentsDirectory().path) ?? "Documents"
    }

#if os(macOS)

    /// Persist a folder picked by the user and start accessing it.
    func select(url newURL: URL) throws {
        guard newURL.isDirectory else {
            throw DownloadFolderError.notADirectory
        }

        let bookmark = try newURL.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        UserDefaults.standard.set(bookmark, forKey: key)

        objectWillChange.send()

        // Replace the previous scope only once the new bookmark was stored.
        self.access = SecurityScopedURL(newURL)
        self.url = newURL
    }

    /// Go back to writing into the app's own Documents directory.
    func reset() {
        UserDefaults.standard.removeObject(forKey: key)

        objectWillChange.send()

        self.access = nil
        self.url = nil
    }

    private func restoreFromBookmark() -> URL? {
        guard let bookmark = UserDefaults.standard.data(forKey: key) else {
            return nil
        }

        var isStale = false

        guard let resolved = try? URL(
            resolvingBookmarkData: bookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            // The bookmark can no longer be resolved, e.g. the folder was deleted.
            UserDefaults.standard.removeObject(forKey: key)

            return nil
        }

        // Access has to be started before the folder can be inspected.
        self.access = SecurityScopedURL(resolved)

        guard resolved.isDirectory else {
            self.access = nil
            UserDefaults.standard.removeObject(forKey: key)

            return nil
        }

        if isStale {
            // Refresh the stored bookmark so that it keeps resolving on later launches.
            if let refreshed = try? resolved.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                UserDefaults.standard.set(refreshed, forKey: key)
            }
        }

        return resolved
    }

#else

    private func restoreFromBookmark() -> URL? {
        // Security scoped bookmarks to arbitrary folders are macOS only. On iOS
        // received files stay in the app's Documents directory, which the Files app
        // already exposes to the user.
        return nil
    }

#endif
}
