/// What features and importers depend on: the live `LCUClient` in the app, a fake in tests.
public protocol LCUConnection: Sendable {
    func send<R: Decodable & Sendable>(_ endpoint: LCUEndpoint<R>) async throws(LCUError) -> R
    /// One stream per subscriber, carrying only the given topics.
    func events(_ topics: Set<LCUTopic>) -> AsyncStream<LCUEvent>
    /// One stream per subscriber: the current state first, then every change.
    func states() -> AsyncStream<ConnectionState>
}
