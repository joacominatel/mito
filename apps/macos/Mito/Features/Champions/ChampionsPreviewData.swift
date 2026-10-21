#if DEBUG
    import MitoAssets
    import MitoCore

    extension ChampionsModel {
        /// A seeded snapshot for previews: a few champions per role around the tier cutoffs.
        static var preview: ChampionsModel {
            ChampionsModel(stats: { PreviewStats() }, gameData: previewGameData)
        }

        private static let previewGameData = GameData(
            champions: [
                (103, "Ahri"), (134, "Syndra"), (238, "Zed"), (3, "Galio"), (86, "Garen"),
                (266, "Aatrox"), (64, "Lee Sin"), (222, "Jinx"), (412, "Thresh"),
            ]
            .map { Champion(id: ChampionID(rawValue: $0), alias: $1, name: $1, iconPath: "") })
    }

    private struct PreviewStats: StatsProvider {
        let meta: SnapshotMeta? = SnapshotMeta(
            patch: Patch(rawValue: "16.21"), queue: QueueID(rawValue: 420),
            bracket: .emeraldPlus, matches: 412_339, blendPatches: [Patch(rawValue: "16.21")],
            thresholds: [.championRole: SampleThreshold(minimum: 200, reliable: 1_000)],
            priors: SmoothingPriors(
                championRoleStrength: 100, championRoleBaseline: 0.5, relationStrength: 200,
                loadoutStrength: 500),
            tierCutoffs: [.s: 0.53, .a: 0.515, .b: 0.5, .c: 0.485])

        private let stats: [Role: [Int: (games: Int, wins: Int)]] = [
            .top: [86: (31_200, 16_380), 266: (24_800, 12_150), 103: (160, 90)],
            .jungle: [64: (40_100, 19_850)],
            .middle: [
                103: (52_300, 28_200), 134: (18_400, 9_480), 238: (36_900, 17_700), 3: (900, 470),
            ],
            .bottom: [222: (61_000, 31_500)],
            .utility: [412: (48_700, 24_100)],
        ]

        func roleGames(for champion: ChampionID) -> [Role: Int] {
            stats.compactMapValues { $0[champion.rawValue]?.games }
        }

        func championRoleStats(in role: Role) -> [ChampionID: ChampionRoleStats] {
            Dictionary(
                uniqueKeysWithValues: (stats[role] ?? [:]).map {
                    (
                        ChampionID(rawValue: $0.key),
                        ChampionRoleStats(
                            games: $0.value.games, wins: $0.value.wins, timelineGames: 0)
                    )
                })
        }
    }
#endif
