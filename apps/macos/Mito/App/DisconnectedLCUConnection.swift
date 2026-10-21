import LCUKit

/// The preview stand-in for `LCUClient`: always searching, never connected.
nonisolated struct DisconnectedLCUConnection: LCUConnection {
    func send<R: Decodable & Sendable>(_ endpoint: LCUEndpoint<R>) async throws(LCUError) -> R {
        throw .notConnected
    }

    func events(_ topics: Set<LCUTopic>) -> AsyncStream<LCUEvent> {
        AsyncStream { $0.finish() }
    }

    func states() -> AsyncStream<ConnectionState> {
        AsyncStream { continuation in
            continuation.yield(.searching)
            continuation.finish()
        }
    }
}
