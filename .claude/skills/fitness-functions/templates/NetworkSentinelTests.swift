// NetworkSentinelTests.swift — fitness function, Pattern 2 (runtime sentinel).
//
// Enforces what a code path may ATTEMPT on the network, not what happens to
// succeed. The sentinel is installed through an injected
// URLSessionConfiguration (protocolClasses), never URLProtocol.registerClass:
// registration is process-global, leaks across parallel tests, and misses
// sessions built from their own configuration.
// Production types therefore take a URLSessionConfiguration in init.
//
// The request log is static (URL loading instantiates the protocol), so it is
// a Mutex and every test that reads it lives in this one .serialized suite.

import Foundation
import Synchronization
import Testing

final class NetworkSentinel: URLProtocol {
    private static let requests = Mutex<[URL]>([])

    static var attemptedURLs: [URL] { requests.withLock { $0 } }
    static func reset() { requests.withLock { $0.removeAll() } }

    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NetworkSentinel.self]
        return configuration
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let url = request.url { Self.requests.withLock { $0.append(url) } }
        // Fail loudly: nothing under test ever reaches a real server.
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct NetworkSentinelTests {
    init() { NetworkSentinel.reset() }

    @Test func cachedSnapshotLoadAttemptsNoRequests() async throws {
        // ADAPT: drive the real path with only storage in memory, e.g.
        //   let store = SnapshotStore(configuration: NetworkSentinel.configuration(), cache: .inMemory(fixture))
        //   _ = try await store.currentSnapshot()
        try await loadCachedSnapshot(configuration: NetworkSentinel.configuration())

        #expect(
            NetworkSentinel.attemptedURLs.isEmpty,
            "a cached snapshot load attempted \(NetworkSentinel.attemptedURLs) — it must be served from disk"
        )
    }

    @Test func lcuClientTalksOnlyToLoopback() async throws {
        // ADAPT: let client = LCUClient(credentials: .fixture, configuration: NetworkSentinel.configuration())
        //        await #expect(throws: LCUError.self) { try await client.send(.gameflowPhase) }
        try await callLCU(configuration: NetworkSentinel.configuration())

        let hosts = NetworkSentinel.attemptedURLs.map { $0.host() ?? "" }
        #expect(!hosts.isEmpty, "the path under test made no request; the sentinel proved nothing")
        #expect(hosts.allSatisfy { $0 == "127.0.0.1" }, "LCUKit reached \(hosts); only 127.0.0.1 is allowed")
    }

    // ADAPT: replace both with the production paths under guarantee.
    private func loadCachedSnapshot(configuration: URLSessionConfiguration) async throws {}

    private func callLCU(configuration: URLSessionConfiguration) async throws {
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let url = try #require(URL(string: "https://127.0.0.1:2999/lol-gameflow/v1/gameflow-phase"))
        _ = try? await session.data(from: url)
    }
}
