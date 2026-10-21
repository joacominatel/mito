import Foundation
import Synchronization

/// Answers each URL with its canned reply (404 otherwise) and records every request. The state is
/// static because URL loading instantiates the protocol; only the serialized
/// `SnapshotDownloaderTests` uses it.
final class RoutingURLProtocol: URLProtocol {
    enum Reply: Sendable {
        case response(status: Int, body: Data)
        case redirect(to: URL)
    }

    private struct State {
        var routes: [URL: Reply] = [:]
        var received: [URL] = []
    }

    private static let state = Mutex(State())

    static var received: [URL] { state.withLock { $0.received } }

    static func serve(_ routes: [URL: Reply]) {
        state.withLock { $0 = State(routes: routes) }
    }

    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RoutingURLProtocol.self]
        return configuration
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let client, let url = request.url else { return }
        let reply = Self.state.withLock { state in
            state.received.append(url)
            return state.routes[url] ?? .response(status: 404, body: Data())
        }
        switch reply {
        case .response(let status, let body):
            guard
                let response = HTTPURLResponse(
                    url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)
            else { return }
            client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client.urlProtocol(self, didLoad: body)
            client.urlProtocolDidFinishLoading(self)
        case .redirect(let location):
            guard
                let response = HTTPURLResponse(
                    url: url, statusCode: 302, httpVersion: "HTTP/1.1",
                    headerFields: ["Location": location.absoluteString])
            else { return }
            client.urlProtocol(
                self, wasRedirectedTo: URLRequest(url: location), redirectResponse: response)
            client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}
