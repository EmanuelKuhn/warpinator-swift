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

enum Failure: Equatable {
    case remoteError(RemoteError)
    case channelFailure
}

enum RemoteState: Equatable {    
    case fetchingCertificate
    case offline
    case waitingForDuplex
    case online
    case retrying
    case unExpectedTransition
//    indirect case failure(_: String)
//    case failedToProcessRemoteCertificate
    case failure(_: Failure)
}

enum RemoteEvent {
    case peerWentOffline, peerCameOnline, channelReady, channelShutdown, channelTransientFailure, gotDuplex, retryTimerFired
    case peerFailure(_: RemoteError)
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
                return .failure(.channelFailure)
            case .channelTransientFailure:
                return .failure(.channelFailure)
            case .gotDuplex:
                return .unExpectedTransition
            case .retryTimerFired:
                return nil
            case .peerFailure(let error):
                return .failure(.remoteError(error))
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
            case .peerFailure(let error):
                return .failure(.remoteError(error))
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
                return .failure(.channelFailure)
            case .channelTransientFailure:
                return .failure(.channelFailure)
            case .gotDuplex:
                return .online
            case .retryTimerFired:
                return nil
            case .peerFailure(let error):
                return .failure(.remoteError(error))
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
                return .failure(.channelFailure)
            case .channelTransientFailure:
                return .failure(.channelFailure)
            case .gotDuplex:
                return nil
            case .retryTimerFired:
                return nil
            case .peerFailure(let error):
                return .failure(.remoteError(error))

            }
        case .failure(_):
            switch event {
            case .peerWentOffline:
                return .offline
            case .peerCameOnline:
                return .fetchingCertificate
            case .channelReady:
                return .online
            case .channelShutdown:
                return .failure(.channelFailure)
            case .channelTransientFailure:
                return .failure(.channelFailure)
            case .gotDuplex:
                return .unExpectedTransition
            case .retryTimerFired:
                return .retrying
            case .peerFailure(let error):
                return .failure(.remoteError(error))

        }

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
                return .failure(.channelFailure)
            case .channelTransientFailure:
                return .failure(.channelFailure)
            case .gotDuplex:
                return .unExpectedTransition
            case .retryTimerFired:
                return nil
            case .peerFailure(let error):
                return .failure(.remoteError(error))
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
