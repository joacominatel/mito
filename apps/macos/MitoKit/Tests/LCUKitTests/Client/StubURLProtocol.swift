import Foundation
import Synchronization

/// Answers every request with one canned reply and records what it received. URL loading
/// instantiates the protocol, so the state is static; only `LCURESTClientTests` uses it, and
/// that suite is serialized.
final class StubURLProtocol: URLProtocol {
    enum Reply: Sendable {
        case response(status: Int, body: Data)
        case failure(URLError.Code)
    }

    struct Received: Sendable {
        let request: URLRequest
        let body: Data?
    }

    private struct State {
        var reply = Reply.response(status: 200, body: Data())
        var received: [Received] = []
    }

    private static let state = Mutex(State())

    static var received: [Received] { state.withLock { $0.received } }

    static func reset(replying reply: Reply) {
        state.withLock { $0 = State(reply: reply) }
    }

    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return configuration
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let reply = Self.state.withLock { state in
            state.received.append(Received(request: request, body: Self.body(of: request)))
            return state.reply
        }
        guard let client, let url = request.url else { return }
        switch reply {
        case .response(let status, let body):
            guard
                let response = HTTPURLResponse(
                    url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)
            else { return }
            client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client.urlProtocol(self, didLoad: body)
            client.urlProtocolDidFinishLoading(self)
        case .failure(let code):
            client.urlProtocol(self, didFailWithError: URLError(code))
        }
    }

    override func stopLoading() {}

    /// URL loading hands a protocol the body as a stream, never as `httpBody`.
    private static func body(of request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            // The buffer outlives the call.
            let count = unsafe stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(contentsOf: buffer[..<count])
        }
        return data
    }
}
