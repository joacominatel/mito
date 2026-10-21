import Foundation
import LCUKit
import Synchronization

/// Every feature subscribes on its own, so states and champ-select sessions replay to late subscribers.
nonisolated final class BroadcastLCUConnection: LCUConnection {
    struct Request: Equatable {
        let method: HTTPMethod
        let path: String
        let body: Data?
    }

    private struct State {
        var bodies: [String: Data]
        var requests: [Request] = []
        var sessions: [LCUEvent] = []
        var finished = false
        var stateSinks: [AsyncStream<ConnectionState>.Continuation] = []
        var sessionSinks: [AsyncStream<LCUEvent>.Continuation] = []
    }

    private let state: Mutex<State>

    init(bodies: [String: Data]) {
        state = Mutex(State(bodies: bodies))
    }

    func writes(_ method: HTTPMethod, _ path: String) -> [Request] {
        state.withLock { $0.requests.filter { $0.method == method && $0.path == path } }
    }

    func send<R: Decodable & Sendable>(_ endpoint: LCUEndpoint<R>) async throws(LCUError) -> R {
        let body = state.withLock { state in
            state.requests.append(
                Request(method: endpoint.method, path: endpoint.path, body: endpoint.body))
            return state.bodies[endpoint.path]
        }
        if endpoint.method != .get { return try endpoint.decode(Data()) }
        guard let body else { throw .http(status: 404, body: Data()) }
        return try endpoint.decode(body)
    }

    func states() -> AsyncStream<ConnectionState> {
        let (stream, sink) = AsyncStream.makeStream(of: ConnectionState.self)
        sink.yield(.connected)
        state.withLock { state in
            if state.finished { sink.finish() } else { state.stateSinks.append(sink) }
        }
        return stream
    }

    func events(_ topics: Set<LCUTopic>) -> AsyncStream<LCUEvent> {
        let (stream, sink) = AsyncStream.makeStream(of: LCUEvent.self)
        guard topics.contains(.champSelectSession) else {
            sink.finish()
            return stream
        }
        state.withLock { state in
            for session in state.sessions { sink.yield(session) }
            if state.finished { sink.finish() } else { state.sessionSinks.append(sink) }
        }
        return stream
    }

    func emit(_ session: Data) {
        let event = LCUEvent(
            uri: LCUEndpoint.champSelectSession.path, eventType: .update, data: session)
        state.withLock { state in
            state.sessions.append(event)
            for sink in state.sessionSinks { sink.yield(event) }
        }
    }

    func finish() {
        state.withLock { state in
            state.finished = true
            for sink in state.stateSinks { sink.finish() }
            for sink in state.sessionSinks { sink.finish() }
        }
    }
}
