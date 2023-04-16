//
//  RemoteLifeCycleStateMachine.swift
//  warpinator-project
//
//  Created by Emanuel on 17/05/2022.
//

import Foundation
import GRPC
import Sodium

import NIO

import Combine


enum RemoteState: Equatable {
    case fetchingCertificate
    case offline
    case waitingForDuplex
    case online
    case channelTransientFailure, channelShutdownFailure
    case retrying
    case unExpectedTransition
//    indirect case failure(_: String)
//    case failedToProcessRemoteCertificate
}

enum RemoteEvent {
    case peerWentOffline, peerCameOnline, channelReady, channelShutdown, channelTransientFailure, gotDuplex, retryTimerFired
}

class StateMachine {
    
    private(set) var state: RemoteState {
        didSet { stateSubject.send(self.state) }
    }
    
    private let stateSubject: PassthroughSubject<RemoteState, Never>
    
    let statePublisher: AnyPublisher<RemoteState, Never>
        
    init() {
        self.state = .offline
        self.stateSubject = PassthroughSubject<RemoteState, Never>()
        self.statePublisher = self.stateSubject.eraseToAnyPublisher()
    }
}

extension StateMachine {
    
    @MainActor
    func tryEvent(_ event: RemoteEvent) {
        if let state = nextState(for: event) {
            
            print("Statemachine transition: \(self.state) -> \(state) for event: \(event)")
            
            self.state = state
        }
        
        print("Statemachine ignored transition: \(self.state) -> \(state) for event: \(event)")
    }
}

extension StateMachine {
    
    private func nextState(for event: RemoteEvent) -> RemoteState? {
        
        switch state {
        case .fetchingCertificate:
            switch event {
            case .peerWentOffline:
                return .offline
            case .peerCameOnline:
                return nil
            case .channelReady:
                return .waitingForDuplex
            case .channelShutdown:
                return .channelShutdownFailure
            case .channelTransientFailure:
                return .channelTransientFailure
            case .gotDuplex:
                return .unExpectedTransition
            case .retryTimerFired:
                return nil
            }
        case .offline:
            switch event {
            case .peerWentOffline:
                return nil
            case .peerCameOnline:
                return .fetchingCertificate
            case .channelReady:
                return .unExpectedTransition
            case .channelShutdown:
                return nil
            case .channelTransientFailure:
                return nil
            case .gotDuplex:
                return .unExpectedTransition
            case .retryTimerFired:
                return nil
            }
        case .waitingForDuplex:
            switch event {
            case .peerWentOffline:
                return .offline
            case .peerCameOnline:
                return nil
            case .channelReady:
                return nil
            case .channelShutdown:
                return .channelShutdownFailure
            case .channelTransientFailure:
                return .channelTransientFailure
            case .gotDuplex:
                return .online
            case .retryTimerFired:
                return nil

            }
        case .online:
            switch event {
            case .peerWentOffline:
                return .offline
            case .peerCameOnline:
                return nil
            case .channelReady:
                return nil
            case .channelShutdown:
                return .channelShutdownFailure
            case .channelTransientFailure:
                return .channelTransientFailure
            case .gotDuplex:
                return nil
            case .retryTimerFired:
                return nil

            }
        case .channelTransientFailure, .channelShutdownFailure:
            switch event {
            case .peerWentOffline:
                return .offline
            case .peerCameOnline:
                return .fetchingCertificate
            case .channelReady:
                return .online
            case .channelShutdown:
                return .channelShutdownFailure
            case .channelTransientFailure:
                return .channelTransientFailure
            case .gotDuplex:
                return .unExpectedTransition
            case .retryTimerFired:
                return .retrying

        }
//        case .failure(errorMsg):
//            switch event {
//            case .peerWentOffline:
//                return .offline
//            case .peerCameOnline:
//                return .fetchingCertificate
//            case .channelReady:
//                return .unExpectedTransition
//            case .channelShutdown:
//                return .channelShutdownFailure
//            case .channelTransientFailure:
//                return .channelTransientFailure
//            case .gotDuplex:
//                return .unExpectedTransition
//            case .retryTimerFired:
//                return .retrying
//        }

        // Should be functionally the same as discovered
        case .retrying:
            switch event {
            case .peerWentOffline:
                return .offline
            case .peerCameOnline:
                return nil
            case .channelReady:
                return .waitingForDuplex
            case .channelShutdown:
                return .channelShutdownFailure
            case .channelTransientFailure:
                return .channelTransientFailure
            case .gotDuplex:
                return .unExpectedTransition
            case .retryTimerFired:
                return nil
            }

        case .unExpectedTransition:
            return .unExpectedTransition
        }
    }
}


extension StateMachine: ConnectivityStateDelegate {
    nonisolated func connectivityStateDidChange(from oldState: ConnectivityState, to newState: ConnectivityState) {
        Task {
            
            // If we're not online, and just connected to remote, set status to waiting for duplex
            if newState == .ready {
                await self.tryEvent(.channelReady)
            }
            
            if newState == .shutdown {
                await self.tryEvent(.channelShutdown)
            }
            
            if newState == .transientFailure {
                await self.tryEvent(.channelTransientFailure)
            }
        }
    }
}
