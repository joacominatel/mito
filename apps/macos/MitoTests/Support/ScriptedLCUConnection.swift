import LCUKit

/// Replays a fixed sequence of connection states, then finishes. `MitoTestSupport` lives in
/// the package and is not linkable from the app tests.
nonisolated struct ScriptedLCUConnection: LCUConnection {
    var script: [ConnectionState]

    func send<R: Decodable & Sendable>(_ endpoint: LCUEndpoint<R>) async throws(LCUError) -> R {
        throw .notConnected
    }

    func events(_ topics: Set<LCUTopic>) -> AsyncStream<LCUEvent> {
        AsyncStream { $0.finish() }
    }

    func states() -> AsyncStream<ConnectionState> {
        AsyncStream { continuation in
            for state in script { continuation.yield(state) }
            continuation.finish()
        }
    }
}
