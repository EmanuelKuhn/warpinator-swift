//
//  WarpRegistrationProvider.swift
//  warpinator-project
//
//  Created by Emanuel on 09/02/2022.
//

import Foundation

import GRPC
import NIOConcurrencyHelpers
import NIOCore


class WarpRegistrationServicer: WarpRegistrationProvider {
    
    let auth: Auth
    
    init(auth: Auth) {
        self.auth = auth
    }
    
    var interceptors: WarpRegistrationServerInterceptorFactoryProtocol?
    
    func requestCertificate(request: RegRequest, context: StatusOnlyCallContext) -> EventLoopFuture<RegResponse> {
        
        print("server: reqcert")
        print(request)
        print(context)
        
        print(context.headers)
        
        
        let response = RegResponse.with({
            $0.lockedCert = auth.getCert()
        })
        
        return context.eventLoop.makeSucceededFuture(response)
    }
    
    
}
