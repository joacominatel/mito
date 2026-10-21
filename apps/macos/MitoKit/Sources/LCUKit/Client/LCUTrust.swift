import Foundation

/// The League client's certificate is self-signed, so its server trust is accepted for
/// `127.0.0.1` and nowhere else (`MITO_CONTEXT.md` §10.3). Every other challenge gets the
/// system's default handling.
enum LCUTrust {
    static func acceptsServerTrust(host: String, authenticationMethod: String) -> Bool {
        host == "127.0.0.1" && authenticationMethod == NSURLAuthenticationMethodServerTrust
    }
}

final class LCUTrustDelegate: NSObject, URLSessionDelegate, Sendable {
    func urlSession(
        _ session: URLSession, didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let space = challenge.protectionSpace
        guard
            LCUTrust.acceptsServerTrust(
                host: space.host, authenticationMethod: space.authenticationMethod),
            let trust = space.serverTrust
        else { return (.performDefaultHandling, nil) }
        return (.useCredential, URLCredential(trust: trust))
    }
}
