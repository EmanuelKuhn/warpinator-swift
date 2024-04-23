//
//  MockRemote.swift
//  warpinator-project
//
//  Created by Emanuel on 23/04/2024.
//

import Foundation

import Combine

@testable import warpinator_project


enum MockError: Error {
    case notImplemented
}

class MockRemote: FullRemoteProtocol {
    var peer: Peer
    
    var transfers: CurrentValueSubject<Array<TransferOp>, Never>
    
    var transfersToRemote: Dictionary<UInt64, TransferToRemote>
    
    var transfersFromRemote: Dictionary<UInt64, TransferFromRemote>
    
    var state: RemoteState = .online
    
    init(peer: Peer, transfersToRemote: Dictionary<UInt64, TransferToRemote> = [:], transfersFromRemote: Dictionary<UInt64, TransferFromRemote> = [:], state: RemoteState = .online) {
        self.peer = peer
        self.transfers = .init([])
        self.transfersToRemote = transfersToRemote
        self.transfersFromRemote = transfersFromRemote
        self.state = state
    }
    
    func ping() async throws {
        return
    }
    
    func requestTransfer(url: URL) async throws {
        throw MockError.notImplemented
    }
    
    func statePublisher() -> AnyPublisher<RemoteState, Never> {
        preconditionFailure("Not implemented")
    }
        
    func cancelTransferOpRequest(timestamp: UInt64) async throws {
        throw MockError.notImplemented
    }
    
    func stopTransfer(timestamp: UInt64, error: Bool) async throws {
        throw MockError.notImplemented
    }
    
    func startTransfer(transferOp: TransferFromRemote, downloader: TransferDownloader) async throws {
        throw MockError.notImplemented
    }
    
    
}

/// A mock `Peer` implementation with fixed resolve() values.
struct TestPeer: Peer {
    
    var name: String
    
    var hostName: String
    
    var fetchCertInfo: FetchCertInfo?
    
    let resolveResult: (String, Int)
    
    func resolve() async throws -> (String, Int) {
        return resolveResult
    }
}
