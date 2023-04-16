//
//  AuthTests.swift
//  warpinator-projectTests
//
//  Created by Emanuel on 13/02/2022.
//

import XCTest
@testable import warpinator_project

import NIOSSL
import Network

class NetworkConfigMock: NetworkConfig {
    
    let _hostname: String
    let _ipAddresses: [IPAddress]
    
    init(hostname: String, ipAddresses: [IPAddress]) {
        self._hostname = hostname
        self._ipAddresses = ipAddresses
    }
    
    override var hostname: String {
        return _hostname
    }
    
    override var ipAddresses: [IPAddress] {
        return _ipAddresses
    }
}

class AuthTests: XCTestCase {
    
    var networkConfig: NetworkConfig = NetworkConfigMock.init(hostname: "hostname", ipAddresses: [IPv4Address("192.168.12.100")!])
    
    override func setUpWithError() throws {
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
    func getAuth(
        hostname: String="hostname",
        ipAddresses: [IPAddress]=[IPv4Address("192.168.12.100")!]
    ) -> Auth {
        return Auth(networkConfig: NetworkConfigMock(hostname: hostname, ipAddresses: ipAddresses), identity: "identity")
    }

    func testDefaultGroupCode() throws {
        let auth = Auth(networkConfig: networkConfig, identity: "identity")
        
        XCTAssert(auth.groupCode == "Warpinator")
    }

    func testSetGroupCode() throws {
        
        let auth = Auth(networkConfig: networkConfig, identity: "identity")
        
        auth.groupCode = "MyGroupCode"
        
        XCTAssert(auth.groupCode == "MyGroupCode")
    }
    
    func testCanOpenLockCert() throws {
        let auth = getAuth()
        
        let lockedCert = """
        1A/Jd9taZO2vk0dPS2hVx8XuMm5tkM8jGqZg9c1CJhJJK9hb61hpkziN8jvtESAzrDfrPdfaNBo8
        wLVuARQRngRleZ7LAlzrDZV3fdDY2LyhGE9xX1gmXD/ijE1dELZPxgZRFBKyiTDSDmPjt1q6rwhd
        Wm0YkeuQv5/XMJfopmMnb3fb6Lh5aEd1uV+G7OE/r74nYElDs/JQ+f/FLFAbRHPBtkjX1AScJl3+
        8p7OkH9J313btIFNefI8osvtc7v8tGCEYj6Tsxdl4k8KABc3NyPH7DLlI9yLxcXxwCxITN2LiUQZ
        CSAnnX8ORx1jUt4bjkXlQ38IvgvOtnd0Tl9eHw08fki8Ilpjmfr5HEopBxQd3Fv596+0EXLIZvp0
        ObUol55setjCSaSDalLTvKSHQbFUktLI2rvVpBJJrRHtFMyDRnNcLQiGiYRRRK3D9QpX0mChKFCl
        xsIQqjU7A4XbK37CmkLqrsfLwprKvxQFkQb3SRKT96+IqWpikwEJTDAOKXXJnr00iQo+FXUqh3z2
        JnMvOJtVT32kIDq7xZ6bdPzPUSKYC3CErkoUs/xacUZKSYLrN2ioBhOcyhTl6v+DKfstlM2v+hFX
        bhfWVaErH+IF7HGyyMnaUeoBe+XxU1Gd0NDW1NNmM3678WYYYo3z2pRU9cLAl8xyGZ+LzibIqbwV
        2LC77aeFmEx5aMgaUUnEPmFiZK2xjbfJiJYYZDj6zf0k+M4tEwdcB4i+dy4ZZCOShLoy8m3HXlmu
        pWBBaHYJOSNpVy3KVVxh6OzVXOD6b/4bGQn6cKec/PqPCnI/Ge+6HzDMt7IO2T20TRW+PL3vFHkF
        E2AFiJd4N1qgQTXzA2Vb7oKbBtkCpW1WDSURiJvIVBWh+OIITz0tBeYvvtdfJMxxZakhxi+DMtJO
        IlRhKMawwKa+FBIyLTKH88/FLJdDVNQaGQPE+5NzdFnpA+4ItvIWPMrBmwc4nllixurpXqhusfwA
        kJ81KoZGOG5lESi+y9HDqCb7lkJdHGGW5fDJJn3BfqBumuQ+BifTse3SmeX/cbiocdapJn2dESlW
        oclcpweBnt7pHykQjOzRQHQh+Xrw2Q73AEB4a/co7QQh+LfoHiIMRRSay7p5ULylv/TiAj/McyQe
        zpwyj5RHXUPy64kC2XHIG3hulAUSPViIF+DMQdUORk9H4rhnPUmGFdrJTzYuPRT3bQQaRYvaR7mu
        +NUUGryMF+ck2RJG1syq/kyB51pqjrn8ievVBNyq5tcC7qTHGmsS+q0gwKjRUolQAVpU67B+c8zq
        Nbm3UpxcTfOXMyBcEWXU03Mcy/P19CwqRbUqFLGogQrJ320ESHpgynZYCi2TP2XcGN7II0bQVjYX
        cxqnCiPKCbUHQSiGfQCFT+/r9Pg/4Fpi2Jx3UohJfFBwHk4mwHU6lTEAJQ6UIgFdZarohP5SQIQU
        AEHk
        """
        
        let result = try auth.processRemoteCertificate(lockedCertificate: lockedCert)
                
        XCTAssert(result.utf8String!.contains("-----BEGIN CERTIFICATE"))
        
        XCTAssert(result.utf8String!.contains("END CERTIFICATE-----"))
    }
        
    func testProcessRemoteCertificateThrowsAuthError() throws {
        let auth = getAuth()
                
        XCTAssertThrowsError(
            try auth.processRemoteCertificate(lockedCertificate: "‹£€€£‹°")
        ) { error in
            XCTAssert(error is AuthError)
        }
        
        XCTAssertThrowsError(
            try auth.processRemoteCertificate(lockedCertificate: "")
        ) { error in
            XCTAssert(error is AuthError)
        }
        
    }

    func testPemEncodingDoesNotIncludeCarriageReturns() throws {
        let auth = getAuth()
        
        let pem = Auth.pemEncoded(certificate: auth.serverIdentity.certificate)
        
        XCTAssertFalse(pem.contains("\r"))
    }
    
    func testPemEncodingIsValid() throws {
        let hostName = "host"
        
        let auth = getAuth(hostname: hostName)
        
        let pem = Auth.pemEncoded(certificate: auth.serverIdentity.certificate)
                        
        let pemBytes = pem.bytes
        
        let nioCertificate = try NIOSSLCertificate(bytes: pemBytes, format: .pem)
        
        let publicKey = try nioCertificate.extractPublicKey().toSPKIBytes()
        
        XCTAssert(publicKey.count > 1)
    }
    
    func testPemEncodedCertificateSubjectSetToHostName() throws {
        let hostName = "host"
        
        let auth = getAuth(hostname: hostName)
        
        let pem = Auth.pemEncoded(certificate: auth.serverIdentity.certificate)
        let pemBytes = pem.bytes
        
        let nioCertificate = try NIOSSLCertificate(bytes: pemBytes, format: .pem)
        
        XCTAssert(nioCertificate.description.contains("common_name=\(hostName)"))
    }
    
    func testUnlockLockedCertificate() throws {
        
        // Arrange
        
        let auth = getAuth()
                
        let expectedUnlockedCert = Auth.pemEncoded(certificate: auth.serverIdentity.certificate)
        
        // Act
        
        let lockedCert = try auth.getLockedCertificate()
        let unlockedCert = try auth.processRemoteCertificate(lockedCertificate: lockedCert)
        
        // Assert

        XCTAssertEqual(expectedUnlockedCert, unlockedCert.utf8String)
    }
    
    func testRegenerateCertificate() throws {
        
        // Arrange
                
        let auth = getAuth()
                
        let originalCert = auth.serverIdentity.certificate
        
        // Act
        auth.regenerateCertificate()
        
        // Assert
        XCTAssertNotEqual(auth.serverIdentity.certificate, originalCert)
    }
}
