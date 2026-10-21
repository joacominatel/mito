import Foundation
import LCUKit
import Synchronization

/// Replays a fixed sequence of connection states to every subscriber, serves canned bodies by
/// path (404 otherwise), and counts each request.
nonisolated final class ServingLCUConnection: LCUConnection {
    private let script: [ConnectionState]
    private let bodies: [String: Data]
    private let requested = Mutex<[String]>([])

    init(script: [ConnectionState], bodies: [String: Data] = [:]) {
        self.script = script
        self.bodies = bodies
    }

    func requests(to path: String) -> Int {
        requested.withLock { $0.filter { $0 == path }.count }
    }

    func send<R: Decodable & Sendable>(_ endpoint: LCUEndpoint<R>) async throws(LCUError) -> R {
        requested.withLock { $0.append(endpoint.path) }
        guard let body = bodies[endpoint.path] else { throw .http(status: 404, body: Data()) }
        return try endpoint.decode(body)
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

enum ClientDataFixture {
    static let version = Data(#""16.21.723.1234""#.utf8)

    static let gameData: [String: Data] = [
        LCUEndpoint.gameDataChampions.path: Data(
            #"[{"id": 103, "alias": "Ahri", "name": "Ahri"}]"#.utf8),
        LCUEndpoint.gameDataItems.path: Data("[]".utf8),
        LCUEndpoint.gameDataPerkStyles.path: Data(#"{"styles": []}"#.utf8),
        LCUEndpoint.gameDataPerks.path: Data("[]".utf8),
        LCUEndpoint.gameDataSummonerSpells.path: Data("[]".utf8),
    ]

    static let staticDataPaths = gameData.keys.sorted()

    static func bodies(version: Bool = true) -> [String: Data] {
        var bodies = gameData
        if version { bodies[LCUEndpoint.gameVersion.path] = Self.version }
        return bodies
    }
}
