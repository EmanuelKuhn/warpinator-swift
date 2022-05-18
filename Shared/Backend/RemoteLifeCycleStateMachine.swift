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

enum RemoteState {
    case mdnsDiscovered
    case mdnsOffline
    case waitingForDuplex
    case online
    case failure
    case channelFailure
    case retry
}


actor RemoteConnectionLifeCycle: ConnectivityStateDelegate {
    
    weak var remote: Remote?
    
    private var retryCounter = 0
    
    init(remote: Remote) {
        self.remote = remote
    }
    
    func mdnsDiscovered(peer: Peer) {
        self.remote?.peer = peer
        
        self.state = .mdnsDiscovered
    }
    
    func mdnsOffline() {
        self.state = .mdnsOffline
    }
    
    /// Statemachine transitions. Given an old state and a new state, execute actions that should occur on transition.
    /// Returns the actual new state. Some transitions are not allowed, and in that cases a different state than newState is returned.
    private func handleTransition(from oldState: RemoteState, to newState: RemoteState) -> RemoteState {
        
        guard let remote = remote else {
            return .mdnsOffline
        }
        
        if oldState == .mdnsOffline && newState != .mdnsDiscovered {
            return .mdnsOffline
        }
        
        switch(newState) {
        case .mdnsOffline:
            remote.deinitClient()
            
            self.retryCounter = 0
            return .mdnsOffline
        case .mdnsDiscovered:
            Task {
                do {
                    try await remote.createConnection()
                    // GRPC channel only tries to connect when the first call happens
                    try await remote.waitingForDuplex()
                    
                    state = .online
                } catch {
                    state = .failure
                }
            }
            
            return .mdnsDiscovered
        case .waitingForDuplex:
            return .waitingForDuplex
        case .online:
            self.retryCounter = 0
            return .online
        case .failure, .channelFailure:
            
            print("\(newState): \(retryCounter)")
            
            let backoff = backoff
            
            DispatchQueue.main.async {
                Timer.scheduledTimer(withTimeInterval: backoff, repeats: false) {_ in
                    print("retry timer fired")

                    Task {
                    
                        await self.updateState(.retry)
                    }
                }
            }
            
            return .failure
        case .retry:
            print("retry: \(retryCounter)")
            
            if oldState == .failure {
                remote.deinitClient()
                
                self.retryCounter += 1
                state = .mdnsDiscovered
                return .retry
            } else {
                return oldState
            }
            
        }
    }
    
    var backoff: Double {
        10.0 * (Double(retryCounter) + 1.0)
    }
    
    /// The current connection state. When set to a new value, handleTransition is called to execute transition actions, and compute the next state.
    /// The next state can be different than the newValue, if the transition is not allowed.
    private(set) var state: RemoteState {
        get {
            _statePublisher.value
        }
        
        set {
            let oldValue = _statePublisher.value
            
            // Compute actual next state based on allowed transitions
            let nextState = self.handleTransition(from: oldValue, to: newValue)
            
            _statePublisher.value = nextState
            
            print("RemoteState \(remote?.id) update \(oldValue) -> \(newValue) --> \(nextState)")
        }
    }
    
    var statePublisher: AnyPublisher<RemoteState, Never> {
        get {
            return _statePublisher.eraseToAnyPublisher()
        }
    }
    
    // Should not be set directly, but only through state
    private var _statePublisher: CurrentValueSubject<RemoteState, Never> = .init(.mdnsOffline)
    
    private func updateState(_ newState: RemoteState) {
        state = newState
    }
    
    /// MARK: ConnectivityStateDelegate
    nonisolated func connectivityStateDidChange(from oldState: ConnectivityState, to newState: ConnectivityState) {
        Task {
            
            // If we're not online, and just connected to remote, set status to waiting for duplex
            if await state == .mdnsDiscovered && newState == .ready {
                await updateState(.waitingForDuplex)
            }
            
            if newState == .shutdown {
                await updateState(.channelFailure)
            }
            
            if newState == .transientFailure {
                await updateState(.channelFailure)
            }
        }
    }
    
}
