import Foundation
import Security
import Testing

@testable import LCUKit

/// A throwaway self-signed certificate (CN=127.0.0.1); its key was discarded.
private let certificateDER = Data(
    base64Encoded: [
        "MIIC6jCCAdKgAwIBAgIUB16R+3eSZP0mABojFgz5EuFclTIwDQYJKoZIhvcNAQELBQAwFDESMBAGA1UEAwwJMTI3",
        "LjAuMC4xMCAXDTI2MTAyMTA0MjAyMloYDzIxMjYwOTI3MDQyMDIyWjAUMRIwEAYDVQQDDAkxMjcuMC4wLjEwggEi",
        "MA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQC5gj9i3JR1Qdj1sMml7wUR6+rItnLaSHqwnrEsuMQ+e5300PSF",
        "eo9KE3ABuxlhSfJlOlWgXduMtxbVnKCYmAdVLGLSAb6G1sfHmZqCdvMfBYStXF92xY26uY7gvKJDMAQn/QDCMN0/",
        "wXtqYgBOVrGowv1aifulo3uox1Cut/iFCaVtqsn51qOI/icmS6C2xFTlXAxEdvxvsWupTteDQF6paZHTl3P7v+Gc",
        "79M5vhGfMYZXqKhTK0Y/V//U4oRcgSVus6TTu9l3GWuKspedknLp6nR4v+gL4iOTdhWSuXcRGDnB77AmwKbrIPzj",
        "3mvUxhIfi7GrugH2zQEpGqA85ub9AgMBAAGjMjAwMB0GA1UdDgQWBBQXGK8bfrKO+6oIM6aO7SuTWPudEzAPBgNV",
        "HRMBAf8EBTADAQH/MA0GCSqGSIb3DQEBCwUAA4IBAQAZZHG9JM+Zc3ABaHGx8SNQPauO5VG7d5FPBFSIyVQAlPM7",
        "djQjn1SIdYxggNREL6le6M2LSZxIS9FU0bPE1pzptohO5n9aworRHzTIOkBKzzhS/NCVjgffRjAgZNF7nRNMeJGb",
        "7zziaGK+0ZSfUpR595gyXyskqjLFb3W7Y8pbUc52piq89KE1kcatID2P8yI91XuOVDgdVIuRvd8tOBRhaioLdkIE",
        "fTn874bigzEk9DLYjlHvJ52D3ICaHMJBiWUZB0/QRTDR/Fpk1ziYfFXMlhrEm7dZn4DSIFBqdv8Rp3OzkTfYMhRe",
        "kh4hPC/EfkX+68DNTOFqZNIjNiy4vUl+",
    ].joined())

/// A protection space carrying a real server trust, as URLSession hands to the delegate.
// Restates the superclass's own conformance; `trust` never changes after init.
private final class TrustedSpace: URLProtectionSpace, @unchecked Sendable {
    private let trust: SecTrust

    init(host: String, method: String, trust: SecTrust) {
        self.trust = trust
        super.init(
            host: host, port: 2999, protocol: NSURLProtectionSpaceHTTPS, realm: nil,
            authenticationMethod: method)
    }

    required init?(coder: NSCoder) { nil }

    override var serverTrust: SecTrust? { trust }
}

private final class NoSender: NSObject, URLAuthenticationChallengeSender {
    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
    func cancel(_ challenge: URLAuthenticationChallenge) {}
}

private func serverTrust() throws -> SecTrust {
    let der = try #require(certificateDER)
    let certificate = try #require(SecCertificateCreateWithData(nil, der as CFData))
    var trust: SecTrust?
    let status = unsafe SecTrustCreateWithCertificates(
        certificate, SecPolicyCreateBasicX509(), &trust)
    try #require(status == errSecSuccess)
    return try #require(trust)
}

private func answer(host: String, method: String = NSURLAuthenticationMethodServerTrust)
    async throws -> (URLSession.AuthChallengeDisposition, URLCredential?)
{
    let space = TrustedSpace(host: host, method: method, trust: try serverTrust())
    let challenge = URLAuthenticationChallenge(
        protectionSpace: space, proposedCredential: nil, previousFailureCount: 0,
        failureResponse: nil, error: nil, sender: NoSender())
    let session = URLSession(configuration: .ephemeral)
    defer { session.invalidateAndCancel() }
    return await LCUTrustDelegate().urlSession(session, didReceive: challenge)
}

struct LCUTrustDelegateTests {
    @Test func trustsTheLoopbackServerWithItsOwnCertificate() async throws {
        let (disposition, credential) = try await answer(host: "127.0.0.1")

        #expect(disposition == .useCredential)
        #expect(credential != nil)
    }

    @Test(arguments: ["localhost", "127.0.0.2", "example.com"])
    func leavesAnyOtherHostsServerTrustToTheSystem(_ host: String) async throws {
        let (disposition, credential) = try await answer(host: host)

        #expect(disposition == .performDefaultHandling)
        #expect(credential == nil)
    }

    @Test func leavesOtherLoopbackChallengesToTheSystem() async throws {
        let (disposition, credential) = try await answer(
            host: "127.0.0.1", method: NSURLAuthenticationMethodHTTPBasic)

        #expect(disposition == .performDefaultHandling)
        #expect(credential == nil)
    }
}
