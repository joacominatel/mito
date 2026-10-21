import Foundation

/// Sends typed endpoints to one running League client. `LCUClient` composes it and makes a
/// new one whenever the credentials change (`MITO_CONTEXT.md` §10.4).
final class LCURESTClient: Sendable {
    private let credentials: LCUCredentials
    private let session: URLSession

    /// Tests inject a stub through `configuration.protocolClasses`.
    init(credentials: LCUCredentials, configuration: URLSessionConfiguration = .ephemeral) {
        self.credentials = credentials
        session = URLSession(
            configuration: configuration, delegate: LCUTrustDelegate(), delegateQueue: nil)
    }

    // The session retains its delegate until it is invalidated.
    deinit { session.finishTasksAndInvalidate() }

    func send<R: Decodable & Sendable>(_ endpoint: LCUEndpoint<R>) async throws(LCUError) -> R {
        let request = try makeRequest(endpoint)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw .transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw .transport("the response is not HTTP")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw .http(status: http.statusCode, body: data)
        }
        return try endpoint.decode(data)
    }

    private func makeRequest<R>(_ endpoint: LCUEndpoint<R>) throws(LCUError) -> URLRequest {
        // A path that does not start with "/" could move the host ("@example.com/…").
        guard endpoint.path.hasPrefix("/"),
            let url = URL(string: "https://127.0.0.1:\(credentials.port)\(endpoint.path)")
        else { throw .encoding("invalid endpoint path \(endpoint.path)") }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.setValue(credentials.authHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body = endpoint.body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        return request
    }
}
