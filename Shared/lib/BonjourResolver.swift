//
//  BonjourResolver.swift
//  warpinator-project
//
//  Taken from: https://developer.apple.com/forums/thread/673771?answerId=662482022#662482022

import Foundation

final class BonjourResolver: NSObject, NetServiceDelegate {
    typealias CompletionHandler = (Result<(String, Int), Error>) -> Void
    
    static func resolve(service: NetService) async throws -> (String, Int) {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                resolve(service: service, completionHandler: { result in
                    continuation.resume(with: result)
                })
            }                
        }
    }
    
    @discardableResult
    static func resolve(service: NetService, completionHandler: @escaping CompletionHandler) -> BonjourResolver {
        precondition(Thread.isMainThread)
        let resolver = BonjourResolver(service: service, completionHandler: completionHandler)
        resolver.start()
        return resolver
    }
    
    private init(service: NetService, completionHandler: @escaping CompletionHandler) {
        // We want our own copy of the service because we’re going to set a
        // delegate on it but `NetService` does not conform to `NSCopying` so
        // instead we create a copy by copying each property.
        let copy = NetService(domain: service.domain, type: service.type, name: service.name)
        self.service = copy
        self.completionHandler = completionHandler
    }
    
    deinit {
        // If these fire the last reference to us was released while the resolve
        // was still in flight.  That should never happen because we retain
        // ourselves on `start`.
        assert(self.service == nil)
        assert(self.completionHandler == nil)
        assert(self.selfRetain == nil)
    }
    
    private var service: NetService? = nil
    private var completionHandler: (CompletionHandler)? = nil
    private var selfRetain: BonjourResolver? = nil
    
    private func start() {
        precondition(Thread.isMainThread)
        guard let service = self.service else { fatalError() }
        service.delegate = self
        service.resolve(withTimeout: 5.0)
        // Form a temporary retain loop to prevent us from being deinitialised
        // while the resolve is in flight.  We break this loop in `stop(with:)`.
        selfRetain = self
    }
    
    func stop() {
        self.stop(with: .failure(CocoaError(.userCancelled)))
    }
    
    private func stop(with result: Result<(String, Int), Error>) {
        precondition(Thread.isMainThread)
        self.service?.delegate = nil
        self.service?.stop()
        self.service = nil
        let completionHandler = self.completionHandler
        self.completionHandler = nil
        completionHandler?(result)
        
        selfRetain = nil
    }
    
    // Adapted from: https://stackoverflow.com/questions/38197198/swift-3-how-to-resolve-netservice-ip
    private static func getNameFromAddresses(addresses: [Data]?) -> String? {
        guard let data = addresses?.first else { return nil }
        
        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        
        var success = false
        
        data.withUnsafeBytes { ptr in
            guard let sockaddr_ptr = ptr.baseAddress?.assumingMemoryBound(to: sockaddr.self) else {
                // handle error
                return
            }
            let sockaddr = sockaddr_ptr.pointee
            guard getnameinfo(sockaddr_ptr, socklen_t(sockaddr.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 else {
                return
            }
            
            success = true
        }
        
        guard success else {
            return nil
        }
        
        let ipAddress = String(cString:hostname)
        return ipAddress
    }
    
    func netServiceDidResolveAddress(_ sender: NetService) {
        let hostName = sender.hostName!
        let port = sender.port
        
        if let ipAddress = BonjourResolver.getNameFromAddresses(addresses: sender.addresses) {
            print("\nBonjourResolver::netServiceDidResolveAddress: resolved ip address: \(ipAddress):\(port)")
            
            self.stop(with: .success((ipAddress, port)))
        } else {
            print("\nBonjourResolver::netServiceDidResolveAddress: resolved hostname: \(hostName):\(port)")
            
            self.stop(with: .success((hostName, port)))
        }
    }
    
    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        let code = (errorDict[NetService.errorCode]?.intValue)
            .flatMap { NetService.ErrorCode.init(rawValue: $0) }
            ?? .unknownError
        let error = NSError(domain: NetService.errorDomain, code: code.rawValue, userInfo: nil)
        self.stop(with: .failure(error))
    }
}
