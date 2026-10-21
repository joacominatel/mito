import Foundation
import Synchronization

/// Answers every request with one canned reply and records what it received. URL loading
/// instantiates the protocol, so the state is static; only `DataDragonClientTests` uses it,
/// and that suite is serialized.
final class StubURLProtocol: URLProtocol {
    enum Reply: Sendable {
        case response(status: Int, body: Data)
        case redirect(to: URL)
        case failure(URLError.Code)
    }

    private struct State {
        var reply = Reply.response(status: 200, body: Data())
        var received: [URLRequest] = []
    }

    private static let state = Mutex(State())

    static var received: [URLRequest] { state.withLock { $0.received } }

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
            state.received.append(request)
            return state.reply
        }
        guard let client, let url = request.url else { return }
        switch reply {
        case .response(let status, let body):
            guard let response = Self.response(url, status: status) else { return }
            client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client.urlProtocol(self, didLoad: body)
            client.urlProtocolDidFinishLoading(self)
        case .redirect(let location):
            guard
                let response = Self.response(
                    url, status: 302, headers: ["Location": location.absoluteString])
            else { return }
            client.urlProtocol(
                self, wasRedirectedTo: URLRequest(url: location), redirectResponse: response)
            client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client.urlProtocolDidFinishLoading(self)
        case .failure(let code):
            client.urlProtocol(self, didFailWithError: URLError(code))
        }
    }

    override func stopLoading() {}

    private static func response(_ url: URL, status: Int, headers: [String: String]? = nil)
        -> HTTPURLResponse?
    {
        HTTPURLResponse(
            url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)
    }
}
