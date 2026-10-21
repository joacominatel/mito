#if DEBUG
    import Foundation
    import LCUKit
    import MitoCore

    extension AppModel {
        /// A connected client with a few champions, a mid pool, and 20 games with Flash on F
        /// in 18.
        static var onboardingPreview: AppModel {
            let app = AppModel(
                connection: PreviewChampionConnection(), personal: PreviewPoolStore())
            app.onboarding.role = .middle
            return app
        }
    }

    private nonisolated struct PreviewChampionConnection: LCUConnection {
        private static let champions = Data(
            """
            [{"id": 103, "name": "Ahri"}, {"id": 134, "name": "Syndra"}, {"id": 238, "name": "Zed"},
             {"id": 3, "name": "Galio"}, {"id": 1, "name": "Annie"}, {"id": 61, "name": "Orianna"}]
            """.utf8)

        /// The shared `GameData` loads all five files; only the champions matter here.
        private static let bodies: [String: Data] = [
            LCUEndpoint.gameDataChampions.path: champions,
            LCUEndpoint.gameDataItems.path: Data("[]".utf8),
            LCUEndpoint.gameDataPerkStyles.path: Data(#"{"styles": []}"#.utf8),
            LCUEndpoint.gameDataPerks.path: Data("[]".utf8),
            LCUEndpoint.gameDataSummonerSpells.path: Data("[]".utf8),
        ]

        func send<R: Decodable & Sendable>(_ endpoint: LCUEndpoint<R>) async throws(LCUError)
            -> R
        {
            guard let body = Self.bodies[endpoint.path] else { throw .notConnected }
            return try endpoint.decode(body)
        }

        func events(_ topics: Set<LCUTopic>) -> AsyncStream<LCUEvent> {
            AsyncStream { $0.finish() }
        }

        func states() -> AsyncStream<ConnectionState> {
            AsyncStream { continuation in
                continuation.yield(.connected)
                continuation.finish()
            }
        }
    }

    private actor PreviewPoolStore: PersonalStore {
        private var pools: [Role: [ChampionID]] = [
            .top: [ChampionID(rawValue: 1)],
            .middle: [103, 134, 238].map(ChampionID.init(rawValue:)),
        ]

        func matches(_ query: MyMatchQuery) -> [MyMatch] {
            let flash = SummonerSpellID(rawValue: 4)
            let ignite = SummonerSpellID(rawValue: 14)
            return (0..<20).map { index in
                let spells =
                    index < 18
                    ? SpellPair(first: ignite, second: flash)
                    : SpellPair(first: flash, second: ignite)
                return MyMatch(
                    game: GameID(rawValue: index), queue: QueueID(rawValue: 420),
                    patch: Patch(rawValue: "16.21"), playedAt: .now,
                    champion: ChampionID(rawValue: 103), role: .middle, win: true, kills: 0,
                    deaths: 0, assists: 0, cs: 0, durationSeconds: 0, opponent: nil,
                    spells: spells, perks: [], items: [], participants: [])
            }
        }

        func pool(for role: Role) -> [PoolEntry] {
            (pools[role] ?? []).enumerated().map {
                PoolEntry(role: role, champion: $1, priority: $0)
            }
        }

        func setPool(_ champions: [ChampionID], for role: Role) { pools[role] = champions }
        func record(_ matches: [MyMatch]) {}
        func overrides() -> [ChampionOverride] { [] }
        func save(_ override: ChampionOverride) {}
        func deleteOverride(champion: ChampionID, role: Role) {}
        func appendImportLog(_ entry: ImportLogEntry) {}
        func importLog(limit: Int) -> [ImportLogEntry] { [] }
        func deleteAll() { pools = [:] }
    }
#endif
