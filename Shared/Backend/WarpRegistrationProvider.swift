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


class WarpRegistrationServicer: WarpRegistrationAsyncProvider {

    
    let auth: Auth
    
    init(auth: Auth) {
        self.auth = auth
    }
    
    var interceptors: WarpRegistrationServerInterceptorFactoryProtocol?
    
    func requestCertificate(request: RegRequest, context: GRPCAsyncServerCallContext) async throws -> RegResponse {
        
        print("server: reqcert")
        print(request)
        print(context)

        print(context.initialResponseMetadata)

        let response = try RegResponse.with({
            $0.lockedCert = try auth.getLockedCertificate()
        })
        
        return response
    }
    
    
}
