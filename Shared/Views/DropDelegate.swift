//
//  DropDelegate.swift
//  warpinator-project
//
//  Created by Emanuel on 24/04/2024.
//

import Foundation

import SwiftUI

import UniformTypeIdentifiers

enum DropDelegateError: Error {
    case invalidURLString
}

struct MyDropDelegate: DropDelegate {
        
    let isTargeted: Binding<Bool>?
    
    let isActive: Bool?
    
    let callback: ([URL]) -> ()
        
    func validateDrop(info: DropInfo) -> Bool {
        return info.hasItemsConforming(to: [.fileURL])
    }
    
    func dropEntered(info: DropInfo) {
        self.isTargeted?.wrappedValue = validateDrop(info: info)
    }
    
    func dropExited(info: DropInfo) {
        self.isTargeted?.wrappedValue = false
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard let isActive = isActive else {
            return nil
        }
        
        if isActive {
            return .init(operation: .copy)
        } else {
            return .init(operation: .forbidden)
        }

    }
    
    func performDrop(info: DropInfo) -> Bool {
        // Check that there are file urls
        guard info.hasItemsConforming(to: [.fileURL]) else { return false }
        
        let providers = info.itemProviders(for: [.fileURL])
        
        let dispatchGroup = DispatchGroup()

        var droppedUrls: [URL] = []
        
        for provider in providers {
            dispatchGroup.enter()
            loadItem(provider: provider) { fileUrl in
                droppedUrls.append(fileUrl)
                dispatchGroup.leave()
            }
        }
        
        dispatchGroup.notify(queue: .global()) {
            callback(droppedUrls)
        }
        
        return true
    }
    
#if os(macOS)
    func loadItem(provider: NSItemProvider, callback: @escaping (URL) -> ()) {
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (item, error) in
            
            if let error = error as NSError? {
                print("performDrop Error: \(error)")
            }
            
            // The item that was dropped is Data...
            if let data = item as? Data {
                
                // Which can be decoded as a string (like "file:///.file/id=6571367.8720033194")
                if let urlString = String(data: data, encoding: .utf8) {
                    do {
                        let resolvedURL = try processURLString(urlString: urlString)
                            callback(resolvedURL)
                    } catch {
                        print("performDrop: Failed to process urlString: \(error)")
                    }
                    
                } else {
                    print("Data could not be decoded into a string.")
                }
            } else {
                print("Item is not of type Data.")
            }
        }

    }
    
    private func processURLString(urlString: String) throws -> URL {
        /// Gets as input a file path like file:///.file/id=6571367.8720033194, and returns a URL that can be used outside of the drop action.
        /// The URL made from the urlString will only allow accessing for a short time, because it resulted froma  drop action.
        /// Thus the URL is first bookmarked and the URL is returned after resolving it from the bookmark.
        
        // Attempt to create a URL from the string
        if let url = URL(string: urlString) {
            // Now the url is a normal looking URL...
            // But, Apparently the URL is only valid for a short time after the drop.
            // To access it longer make a bookmark
            let bookmarkData = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: [.isDirectoryKey, .fileSizeKey])

            var stale = false
            let resolvedURL = try URL(resolvingBookmarkData: bookmarkData, options: [.withSecurityScope], bookmarkDataIsStale: &stale)
            
            // resolvedURL is almost the same as url (might have extra '/' in the path), but now the url can be accessed longer.
                            
            if stale {
                print("Warning: for some reason the bookmark is stale")
            }
            
            return resolvedURL
        } else {
            throw DropDelegateError.invalidURLString
        }
    }
#else
    func loadItem(provider: provider) {
        print("Not implemented: loadItem(provider: \(provider)")
    }
#endif
}
