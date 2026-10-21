import Foundation
import LCUKit
import Synchronization

/// Serves canned bodies by path (404 otherwise), records each request, and lets the test push
/// connection states and champ-select events.
nonisolated final class DraftTestConnection: LCUConnection {
    private let bodies: Mutex<[String: Data]>
    private let requested = Mutex<[String]>([])
    private let stateStream: AsyncStream<ConnectionState>
    private let stateSink: AsyncStream<ConnectionState>.Continuation
    private let eventStream: AsyncStream<LCUEvent>
    private let eventSink: AsyncStream<LCUEvent>.Continuation

    init(bodies: [String: Data] = [:]) {
        self.bodies = Mutex(bodies)
        (stateStream, stateSink) = AsyncStream.makeStream()
        (eventStream, eventSink) = AsyncStream.makeStream()
    }

    var requests: [String] { requested.withLock { $0 } }

    func serve(_ path: String, _ body: Data?) {
        bodies.withLock { $0[path] = body }
    }

    func send<R: Decodable & Sendable>(_ endpoint: LCUEndpoint<R>) async throws(LCUError) -> R {
        requested.withLock { $0.append(endpoint.path) }
        guard let body = bodies.withLock({ $0[endpoint.path] }) else {
            throw .http(status: 404, body: Data())
        }
        return try endpoint.decode(body)
    }

    /// Single subscriber: the model under test.
    func events(_ topics: Set<LCUTopic>) -> AsyncStream<LCUEvent> { eventStream }

    /// Single subscriber: the model under test.
    func states() -> AsyncStream<ConnectionState> { stateStream }

    func enter(_ state: ConnectionState) {
        stateSink.yield(state)
    }

    func emit(_ type: LCUEvent.EventType, _ data: Data = Data("{}".utf8)) {
        eventSink.yield(LCUEvent(uri: "/lol-champ-select/v1/session", eventType: type, data: data))
    }

    func finish() {
        stateSink.finish()
        eventSink.finish()
    }
}
