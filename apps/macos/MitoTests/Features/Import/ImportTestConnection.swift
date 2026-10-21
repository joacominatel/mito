import Foundation
import LCUKit
import Synchronization
import Testing

/// Serves canned GET bodies by path (404 otherwise), accepts every write, records each request
/// with its body, and lets the test push connection states and champ-select events.
nonisolated final class ImportTestConnection: LCUConnection {
    struct Request: Equatable {
        let method: HTTPMethod
        let path: String
        let body: Data?
    }

    private let bodies = Mutex<[String: Data]>([:])
    private let recorded = Mutex<[Request]>([])
    private let stateStream: AsyncStream<ConnectionState>
    private let stateSink: AsyncStream<ConnectionState>.Continuation
    private let eventStream: AsyncStream<LCUEvent>
    private let eventSink: AsyncStream<LCUEvent>.Continuation

    init() {
        (stateStream, stateSink) = AsyncStream.makeStream()
        (eventStream, eventSink) = AsyncStream.makeStream()
    }

    var requests: [Request] { recorded.withLock { $0 } }

    func writes(_ method: HTTPMethod, _ path: String) -> [Request] {
        requests.filter { $0.method == method && $0.path == path }
    }

    func serve(_ path: String, _ body: Data) {
        bodies.withLock { $0[path] = body }
    }

    func send<R: Decodable & Sendable>(_ endpoint: LCUEndpoint<R>) async throws(LCUError) -> R {
        recorded.withLock {
            $0.append(Request(method: endpoint.method, path: endpoint.path, body: endpoint.body))
        }
        if endpoint.method != .get { return try endpoint.decode(Data()) }
        guard let body = bodies.withLock({ $0[endpoint.path] }) else {
            throw .http(status: 404, body: Data())
        }
        return try endpoint.decode(body)
    }

    /// Single subscriber: the model under test, which only follows the champ-select session.
    func events(_ topics: Set<LCUTopic>) -> AsyncStream<LCUEvent> { eventStream }

    /// Single subscriber: the model under test.
    func states() -> AsyncStream<ConnectionState> { stateStream }

    func enter(_ state: ConnectionState) {
        stateSink.yield(state)
    }

    func emit(_ session: Data) {
        eventSink.yield(
            LCUEvent(uri: LCUEndpoint.champSelectSession.path, eventType: .update, data: session))
    }

    func emitDelete() {
        eventSink.yield(
            LCUEvent(
                uri: LCUEndpoint.champSelectSession.path, eventType: .delete,
                data: Data("null".utf8)))
    }

    func finish() {
        stateSink.finish()
        eventSink.finish()
    }
}

enum ImportFixture {
    static let cases = URL(filePath: #filePath)
        .deletingLastPathComponent()  // Import/
        .deletingLastPathComponent()  // Features/
        .deletingLastPathComponent()  // MitoTests/
        .deletingLastPathComponent()  // macos/
        .deletingLastPathComponent()  // apps/
        .deletingLastPathComponent()  // repository root
        .appending(path: "fixtures/lcu/cases", directoryHint: .isDirectory)

    static func data(_ name: String, in folder: String = "champ-select") throws -> Data {
        try Data(contentsOf: cases.appending(path: "\(folder)/\(name).json"))
    }

    /// `ban-pick-in-progress` (local cell 2, MIDDLE, hovering Ahri) with its pick completed.
    static func lockedSession(champion: Int = 103, mySpells: [Int] = [4, 14]) throws -> Data {
        var session = try #require(
            try JSONSerialization.jsonObject(with: data("ban-pick-in-progress")) as? [String: Any])
        let team = try #require(session["myTeam"] as? [[String: Any]])
        session["myTeam"] = team.map { member in
            guard member["cellId"] as? Int == 2 else { return member }
            var me = member
            me["spell1Id"] = mySpells[0]
            me["spell2Id"] = mySpells[1]
            return me
        }
        let actions = try #require(session["actions"] as? [[[String: Any]]])
        session["actions"] = actions.map { group in
            group.map { action in
                guard action["id"] as? Int == 14 else { return action }
                var locked = action
                locked["championId"] = champion
                locked["isInProgress"] = false
                locked["completed"] = true
                return locked
            }
        }
        return try JSONSerialization.data(withJSONObject: session)
    }
}
