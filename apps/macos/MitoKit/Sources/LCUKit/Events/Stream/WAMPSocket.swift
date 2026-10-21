import Foundation

/// A text-frame WebSocket to the League client; tests replace it with an in-memory fake.
protocol WAMPSocket: Sendable {
    func send(_ frame: String) async throws
    /// The next text frame. Throws once the socket is closed or has failed.
    func receive() async throws -> String
    /// Idempotent; a pending `receive()` throws.
    func close()
}

final class URLSessionWAMPSocket: WAMPSocket {
    private let session: URLSession
    private let task: URLSessionWebSocketTask

    /// Connects right away; the handshake reuses the REST client's loopback-only trust.
    init(credentials: LCUCredentials, configuration: URLSessionConfiguration = .ephemeral)
        throws(LCUError)
    {
        let request = try Self.request(credentials)
        session = URLSession(
            configuration: configuration, delegate: LCUTrustDelegate(), delegateQueue: nil)
        task = session.webSocketTask(with: request)
        task.resume()
    }

    // The session retains its delegate until it is invalidated.
    deinit { session.invalidateAndCancel() }

    static func request(_ credentials: LCUCredentials) throws(LCUError) -> URLRequest {
        guard let url = URL(string: "wss://127.0.0.1:\(credentials.port)/") else {
            throw .encoding("invalid port \(credentials.port)")
        }
        var request = URLRequest(url: url)
        request.setValue(credentials.authHeader, forHTTPHeaderField: "Authorization")
        request.setValue("wamp", forHTTPHeaderField: "Sec-WebSocket-Protocol")
        return request
    }

    func send(_ frame: String) async throws {
        try await task.send(.string(frame))
    }

    func receive() async throws -> String {
        while true {
            switch try await task.receive() {
            case .string(let text): return text
            case .data(let data): return String(decoding: data, as: UTF8.self)
            @unknown default: continue
            }
        }
    }

    func close() {
        task.cancel(with: .goingAway, reason: nil)
    }
}
