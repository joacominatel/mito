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

/// Upserts by game ID like `PersonalDatabase`; the pool and overrides are fixed. Writes other
/// than the history do nothing. `MitoTestSupport` is not linkable from the app tests.
actor HistoryTestStore: PersonalStore {
    private var byGame: [GameID: MyMatch]
    private var failure: PersonalStoreError?
    private let poolEntries: [PoolEntry]
    private let championOverrides: [ChampionOverride]

    init(
        matches: [MyMatch] = [], pool: [PoolEntry] = [], overrides: [ChampionOverride] = [],
        failure: PersonalStoreError? = nil
    ) {
        byGame = Dictionary(matches.map { ($0.game, $0) }, uniquingKeysWith: { $1 })
        poolEntries = pool
        championOverrides = overrides
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

    func pool(for role: Role) -> [PoolEntry] { poolEntries.filter { $0.role == role } }
    func setPool(_ champions: [ChampionID], for role: Role) {}
    func overrides() -> [ChampionOverride] { championOverrides }
    func save(_ override: ChampionOverride) {}
    func deleteOverride(champion: ChampionID, role: Role) {}
    func appendImportLog(_ entry: ImportLogEntry) {}
    func importLog(limit: Int) -> [ImportLogEntry] { [] }
    func deleteAll() { byGame = [:] }
}

/// One of the user's games, played `hoursAgo` before `TestGame.now`.
enum TestGame {
    static let now = Date(timeIntervalSince1970: 1_792_000_000)

    static func make(
        _ id: Int, champion: Int, role: Role? = .middle, opponent: Int? = nil, win: Bool,
        minutes: Int = 30, hoursAgo: Double = 0, kills: Int = 5, deaths: Int = 5,
        assists: Int = 5, cs: Int = 200
    ) -> MyMatch {
        MyMatch(
            game: GameID(rawValue: id), queue: QueueID(rawValue: 420),
            patch: Patch(rawValue: "16.21"), playedAt: now.addingTimeInterval(-hoursAgo * 3_600),
            champion: ChampionID(rawValue: champion), role: role, win: win, kills: kills,
            deaths: deaths, assists: assists, cs: cs, durationSeconds: minutes * 60,
            opponent: opponent.map(ChampionID.init(rawValue:)),
            spells: SpellPair(
                first: SummonerSpellID(rawValue: 4), second: SummonerSpellID(rawValue: 14)),
            perks: [], items: [], participants: [])
    }
}

/// A snapshot with one `champ_role_stats` row per entry, at the default priors.
struct TestStats: StatsProvider {
    var rows: [Role: [ChampionID: ChampionRoleStats]] = [:]

    var meta: SnapshotMeta? {
        SnapshotMeta(
            patch: Patch(rawValue: "16.21"), queue: QueueID(rawValue: 420),
            bracket: .emeraldPlus, matches: 100_000, blendPatches: [Patch(rawValue: "16.21")],
            thresholds: [:],
            priors: SmoothingPriors(
                championRoleStrength: 100, championRoleBaseline: 0.5, relationStrength: 200,
                loadoutStrength: 500),
            tierCutoffs: [:])
    }

    func roleGames(for champion: ChampionID) -> [Role: Int] { [:] }

    func championRoleStats(in role: Role) -> [ChampionID: ChampionRoleStats] {
        rows[role] ?? [:]
    }
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

    static func mastery() throws -> Data {
        try Data(contentsOf: cases.appending(path: "mastery.json"))
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
