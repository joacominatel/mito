public import Foundation
public import LCUKit
import Synchronization

/// Serves canned responses and events, and records every request it receives.
///
/// Responses for the same method and path are served in order; the last one keeps answering.
/// A request with no response gets a 404, like the real client. The event stream yields the
/// matching events in order and then finishes; `t_ms` is ignored.
public final class FakeLCUConnection: LCUConnection {
    public struct Response: Sendable {
        public let method: HTTPMethod
        public let path: String
        public let status: Int
        public let body: Data

        public init(method: HTTPMethod, path: String, status: Int = 200, body: Data = Data()) {
            self.method = method
            self.path = path
            self.status = status
            self.body = body
        }

        public init(method: HTTPMethod, path: String, status: Int = 200, json: String) {
            self.init(method: method, path: path, status: status, body: Data(json.utf8))
        }
    }

    public struct Event: Sendable {
        public let topic: LCUTopic
        public let event: LCUEvent

        public init(topic: LCUTopic, event: LCUEvent) {
            self.topic = topic
            self.event = event
        }
    }

    public struct Request: Equatable, Sendable {
        public let method: HTTPMethod
        public let path: String
        public let body: Data?

        public init(method: HTTPMethod, path: String, body: Data?) {
            self.method = method
            self.path = path
            self.body = body
        }
    }

    public enum ScenarioError: Error, Equatable {
        case missingScenario(String)
        case malformedLine(file: String, line: Int)
    }

    private struct Route: Hashable {
        let method: HTTPMethod
        let path: String
    }

    private struct State {
        var pending: [Route: [Response]]
        var requests: [Request] = []
        var connectionState: ConnectionState
        var stateSubscribers: [UUID: AsyncStream<ConnectionState>.Continuation] = [:]
    }

    private let state: Mutex<State>
    private let scriptedEvents: [Event]

    public init(
        responses: [Response] = [], events: [Event] = [], state: ConnectionState = .connected
    ) {
        self.state = Mutex(
            State(
                pending: Dictionary(grouping: responses) {
                    Route(method: $0.method, path: $0.path)
                },
                connectionState: state
            )
        )
        scriptedEvents = events
    }

    /// Loads `fixtures/lcu/<scenario>/rest.jsonl` and `events.jsonl` (recording format v0).
    public convenience init(scenario: String) throws {
        try self.init(directory: Fixtures.url("lcu/\(scenario)"))
    }

    public convenience init(directory: URL) throws {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            throw ScenarioError.missingScenario(directory.path)
        }
        let responses = try Self.jsonLines(directory.appending(path: "rest.jsonl")).map {
            line, object -> Response in
            guard let method = (object["method"] as? String).flatMap(HTTPMethod.init(rawValue:)),
                let path = object["path"] as? String,
                let status = object["status"] as? Int
            else { throw ScenarioError.malformedLine(file: "rest.jsonl", line: line) }
            return Response(
                method: method, path: path, status: status, body: try Self.raw(object["body"]))
        }
        let events = try Self.jsonLines(directory.appending(path: "events.jsonl")).compactMap {
            line, object -> Event? in
            guard let topicName = object["topic"] as? String,
                let uri = object["uri"] as? String,
                let eventType = object["eventType"] as? String
            else { throw ScenarioError.malformedLine(file: "events.jsonl", line: line) }
            guard let topic = LCUTopic(rawValue: topicName) else { return nil }
            let event = LCUEvent(
                uri: uri, eventType: .init(eventType), data: try Self.raw(object["data"]))
            return Event(topic: topic, event: event)
        }
        self.init(responses: responses, events: events)
    }

    public var requests: [Request] { state.withLock { $0.requests } }

    /// Every request that is not a `GET`.
    public var writes: [Request] { requests.filter { $0.method != .get } }

    public func send<R: Decodable & Sendable>(_ endpoint: LCUEndpoint<R>) async throws(LCUError)
        -> R
    {
        let route = Route(method: endpoint.method, path: endpoint.path)
        let response = state.withLock { state -> Response? in
            state.requests.append(
                Request(method: endpoint.method, path: endpoint.path, body: endpoint.body))
            guard let queue = state.pending[route], let first = queue.first else { return nil }
            if queue.count > 1 { state.pending[route] = Array(queue.dropFirst()) }
            return first
        }
        guard let response else { throw .http(status: 404, body: Data()) }
        guard (200..<300).contains(response.status) else {
            throw .http(status: response.status, body: response.body)
        }
        return try endpoint.decode(response.body)
    }

    public func events(_ topics: Set<LCUTopic>) -> AsyncStream<LCUEvent> {
        let matching = scriptedEvents.filter { topics.contains($0.topic) }.map(\.event)
        return AsyncStream { continuation in
            for event in matching { continuation.yield(event) }
            continuation.finish()
        }
    }

    public func states() -> AsyncStream<ConnectionState> {
        let (stream, continuation) = AsyncStream.makeStream(of: ConnectionState.self)
        let id = UUID()
        state.withLock { state in
            state.stateSubscribers[id] = continuation
            continuation.yield(state.connectionState)
        }
        continuation.onTermination = { [weak self] _ in
            _ = self?.state.withLock { $0.stateSubscribers.removeValue(forKey: id) }
        }
        return stream
    }

    /// Records the new state and yields it to every live `states()` subscriber.
    public func setState(_ newState: ConnectionState) {
        let subscribers = state.withLock { state in
            state.connectionState = newState
            return Array(state.stateSubscribers.values)
        }
        for subscriber in subscribers { subscriber.yield(newState) }
    }

    /// A missing file is an empty list: a scenario may record only REST or only events.
    private static func jsonLines(_ url: URL) throws -> [(line: Int, object: [String: Any])] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .filter { !$0.element.allSatisfy(\.isWhitespace) }
            .map { index, text in
                guard
                    let object = try? JSONSerialization.jsonObject(with: Data(text.utf8))
                        as? [String: Any]
                else {
                    throw ScenarioError.malformedLine(file: url.lastPathComponent, line: index + 1)
                }
                return (index + 1, object)
            }
    }

    /// `null` or an absent member is an empty body, as a 204 sends.
    private static func raw(_ value: Any?) throws -> Data {
        guard let value, !(value is NSNull) else { return Data() }
        return try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
    }
}
