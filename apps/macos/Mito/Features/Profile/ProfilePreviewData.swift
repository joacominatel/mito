#if DEBUG
    import Foundation
    import MitoAssets
    import MitoCore

    extension ProfileModel {
        /// A seeded history for previews: a few champions per role, a streak, short games.
        static var preview: ProfileModel {
            ProfileModel(
                connection: DisconnectedLCUConnection(), store: PreviewProfileStore(),
                stats: { PreviewProfileStats() })
        }

        static let previewGameData = GameData(
            champions: [
                (103, "Ahri"), (134, "Syndra"), (238, "Zed"), (3, "Galio"), (86, "Garen"),
                (266, "Aatrox"), (64, "Lee Sin"), (222, "Jinx"), (412, "Thresh"), (84, "Akali"),
            ]
            .map { Champion(id: ChampionID(rawValue: $0), alias: $1, name: $1, iconPath: "") })
    }

    private actor PreviewProfileStore: PersonalStore {
        private let games: [MyMatch] = {
            // (champion, role, opponent, win, minutes)
            let plan: [(Int, Role, Int, Bool, Int)] =
                [(103, .middle, 238, false, 31), (103, .middle, 238, false, 34)]
                + [(134, .middle, 3, false, 29)]
                + (0..<8).map { (103, .middle, 238, $0 % 3 != 0, 22) }
                + (0..<7).map { (103, .middle, 84, $0 % 2 == 0, 33) }
                + (0..<5).map { (134, .middle, 84, $0 == 0, 30) }
                + (0..<6).map { (86, .top, 266, $0 != 2, 27) }
                + (0..<4).map { (222, .bottom, 222, $0 % 2 == 0, 31) }
            let now = Date.now
            return plan.enumerated().map { index, game in
                MyMatch(
                    game: GameID(rawValue: 7_000_000_000 + index),
                    queue: QueueID(rawValue: 420), patch: Patch(rawValue: "16.21"),
                    playedAt: now.addingTimeInterval(-Double(index) * 20_000),
                    champion: ChampionID(rawValue: game.0), role: game.1, win: game.3,
                    kills: game.3 ? 8 : 3, deaths: game.3 ? 3 : 6, assists: 7,
                    cs: game.4 * 7, durationSeconds: game.4 * 60,
                    opponent: ChampionID(rawValue: game.2),
                    spells: SpellPair(
                        first: SummonerSpellID(rawValue: 4), second: SummonerSpellID(rawValue: 14)),
                    perks: [], items: [], participants: [])
            }
        }()

        func record(_ matches: [MyMatch]) {}
        func matches(_ query: MyMatchQuery) -> [MyMatch] { games }
        func pool(for role: Role) -> [PoolEntry] {
            role == .middle
                ? [PoolEntry(role: .middle, champion: ChampionID(rawValue: 134), priority: 0)] : []
        }
        func setPool(_ champions: [ChampionID], for role: Role) {}
        func overrides() -> [ChampionOverride] { [] }
        func save(_ override: ChampionOverride) {}
        func deleteOverride(champion: ChampionID, role: Role) {}
        func appendImportLog(_ entry: ImportLogEntry) {}
        func importLog(limit: Int) -> [ImportLogEntry] { [] }
        func deleteAll() {}
    }

    private struct PreviewProfileStats: StatsProvider {
        let meta: SnapshotMeta? = SnapshotMeta(
            patch: Patch(rawValue: "16.21"), queue: QueueID(rawValue: 420),
            bracket: .emeraldPlus, matches: 412_339, blendPatches: [Patch(rawValue: "16.21")],
            thresholds: [.championRole: SampleThreshold(minimum: 200, reliable: 1_000)],
            priors: SmoothingPriors(
                championRoleStrength: 100, championRoleBaseline: 0.5, relationStrength: 200,
                loadoutStrength: 500),
            tierCutoffs: [.s: 0.53, .a: 0.515, .b: 0.5, .c: 0.485])

        func roleGames(for champion: ChampionID) -> [Role: Int] { [:] }

        func championRoleStats(in role: Role) -> [ChampionID: ChampionRoleStats] {
            let average = ChampionRoleStats(
                games: 40_000, wins: 20_400, timelineGames: 0, kills: 240_000,
                deaths: 220_000, assists: 280_000, cs: 7_200_000, minutes: 1_200_000)
            return [103, 134, 86, 222].reduce(into: [:]) { $0[ChampionID(rawValue: $1)] = average }
        }
    }
#endif
