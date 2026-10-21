import Foundation
import LCUKit
import MitoCore
import Synchronization
import Testing

/// Replays its states and gameflow phases to every subscriber, then finishes; serves bodies by
/// full path, query included (404 otherwise), and counts each request.
nonisolated final class HistoryTestConnection: LCUConnection {
    private let script: [ConnectionState]
    private let phases: [String]
    private let bodies: Mutex<[String: Data]>
    private let requested = Mutex<[String]>([])

    init(script: [ConnectionState], phases: [String] = [], bodies: [String: Data] = [:]) {
        self.script = script
        self.phases = phases
        self.bodies = Mutex(bodies)
    }

    func serve(_ path: String, _ body: Data?) {
        bodies.withLock { $0[path] = body }
    }

    func requests(to path: String) -> Int {
        requested.withLock { $0.count { $0 == path } }
    }

    func send<R: Decodable & Sendable>(_ endpoint: LCUEndpoint<R>) async throws(LCUError) -> R {
        requested.withLock { $0.append(endpoint.path) }
        guard let body = bodies.withLock({ $0[endpoint.path] }) else {
            throw .http(status: 404, body: Data())
        }
        return try endpoint.decode(body)
    }

    func events(_ topics: Set<LCUTopic>) -> AsyncStream<LCUEvent> {
        let phases = topics.contains(.gameflowPhase) ? phases : []
        return AsyncStream { continuation in
            for phase in phases {
                continuation.yield(
                    LCUEvent(
                        uri: LCUEndpoint.gameflowPhase.path, eventType: .update,
                        data: Data("\"\(phase)\"".utf8)))
            }
            continuation.finish()
        }
    }

    func states() -> AsyncStream<ConnectionState> {
        AsyncStream { continuation in
            for state in script { continuation.yield(state) }
            continuation.finish()
        }
    }
}

/// Upserts by game ID like `PersonalDatabase`; only the history calls are real. `MitoTestSupport`
/// is not linkable from the app tests.
actor HistoryTestStore: PersonalStore {
    private var byGame: [GameID: MyMatch]
    private var failure: PersonalStoreError?

    init(matches: [MyMatch] = [], failure: PersonalStoreError? = nil) {
        byGame = Dictionary(matches.map { ($0.game, $0) }, uniquingKeysWith: { $1 })
        self.failure = failure
    }

    var stored: [MyMatch] { byGame.values.sorted { $0.game.rawValue < $1.game.rawValue } }

    func record(_ matches: [MyMatch]) throws(PersonalStoreError) {
        if let failure { throw failure }
        for match in matches { byGame[match.game] = match }
    }

    func matches(_ query: MyMatchQuery) throws(PersonalStoreError) -> [MyMatch] {
        if let failure { throw failure }
        let newest = byGame.values.sorted { $0.playedAt > $1.playedAt }
        return query.limit.map { Array(newest.prefix($0)) } ?? newest
    }

    func pool(for role: Role) -> [PoolEntry] { [] }
    func setPool(_ champions: [ChampionID], for role: Role) {}
    func overrides() -> [ChampionOverride] { [] }
    func save(_ override: ChampionOverride) {}
    func deleteOverride(champion: ChampionID, role: Role) {}
    func appendImportLog(_ entry: ImportLogEntry) {}
    func importLog(limit: Int) -> [ImportLogEntry] { [] }
    func deleteAll() { byGame = [:] }
}

/// Bodies built from `fixtures/lcu/cases/history`, whose local player is `localPUUID`.
enum HistoryFixture {
    static let localPUUID = "fake-puuid-local"
    static let summoner = Data(#"{"puuid": "fake-puuid-local", "summonerLevel": 30}"#.utf8)
    static let emptyPage = page([])

    static let cases = URL(filePath: #filePath)
        .deletingLastPathComponent()  // Profile/
        .deletingLastPathComponent()  // Features/
        .deletingLastPathComponent()  // MitoTests/
        .deletingLastPathComponent()  // macos/
        .deletingLastPathComponent()  // apps/
        .deletingLastPathComponent()  // repository root
        .appending(path: "fixtures/lcu/cases/history", directoryHint: .isDirectory)

    /// `ranked-page`'s three games, newest first: 1 and 2 complete, 3 with no opponent.
    static func rankedGames() throws -> [[String: Any]] {
        let data = try Data(contentsOf: cases.appending(path: "ranked-page.json"))
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let games = try #require(root["games"] as? [String: Any])
        return try #require(games["games"] as? [[String: Any]])
    }

    /// `game` with only the participants whose IDs are listed, as the history list can send it.
    static func trimmed(_ game: [String: Any], keeping ids: Set<Int>) -> [String: Any] {
        var game = game
        let participants = (game["participants"] as? [[String: Any]]) ?? []
        game["participants"] = participants.filter {
            ids.contains(($0["participantId"] as? Int) ?? 0)
        }
        return game
    }

    static func page(_ games: [[String: Any]]) -> Data {
        json(["games": ["games": games]])
    }

    static func json(_ object: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }

    static func pagePath(_ begin: Int) -> String {
        LCUEndpoint.matchHistory(begIndex: begin, endIndex: begin + 20, localPUUID: nil).path
    }

    static func gamePath(_ id: Int) -> String {
        LCUEndpoint.matchHistoryGame(GameID(rawValue: id), localPUUID: nil).path
    }

    static func matches(in page: Data) throws -> [MyMatch] {
        try LCUEndpoint.matchHistory(localPUUID: localPUUID).decode(page).matches
    }
}
