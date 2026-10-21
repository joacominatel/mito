import Foundation
import Testing

@testable import LCUKit

struct LCUTrustTests {
    @Test func acceptsTheServerTrustOfLoopback() {
        #expect(
            LCUTrust.acceptsServerTrust(
                host: "127.0.0.1", authenticationMethod: NSURLAuthenticationMethodServerTrust))
    }

    @Test(arguments: [
        "localhost", "::1", "127.0.0.2", "127.0.0.1.example.com", "example.com", "riotgames.com",
        "",
    ])
    func rejectsTheServerTrustOfAnyOtherHost(_ host: String) {
        #expect(
            !LCUTrust.acceptsServerTrust(
                host: host, authenticationMethod: NSURLAuthenticationMethodServerTrust))
    }

    @Test(arguments: [
        NSURLAuthenticationMethodClientCertificate, NSURLAuthenticationMethodHTTPBasic,
        NSURLAuthenticationMethodDefault,
    ])
    func leavesOtherLoopbackChallengesToDefaultHandling(_ method: String) {
        #expect(!LCUTrust.acceptsServerTrust(host: "127.0.0.1", authenticationMethod: method))
    }
}
