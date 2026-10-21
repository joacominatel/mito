import Foundation
import MitoCore
import Testing

@testable import MitoStore

struct SnapshotReaderTests {
    private static let zed = ChampionID(rawValue: 238)

    // MARK: Opening

    @Test func aMissingFileIsUnreadable() throws {
        try SnapshotCopy.withDirectory { directory in
            #expect(throws: SnapshotReadError.unreadable) {
                try SnapshotReader(fileURL: directory.appending(path: "absent.sqlite"))
            }
        }
    }

    @Test func aFileThatIsNotSQLiteIsUnreadable() throws {
        try SnapshotCopy.withDirectory { directory in
            let file = directory.appending(path: "corrupt.sqlite")
            try Data(repeating: 0x5A, count: 4096).write(to: file)
            #expect(throws: SnapshotReadError.unreadable) {
                try SnapshotReader(fileURL: file)
            }
        }
    }

    @Test func aTruncatedSnapshotIsAnError() throws {
        try SnapshotCopy.withDirectory { directory in
            let file = directory.appending(path: "truncated.sqlite")
            try Data(try Data(contentsOf: SnapshotCopy.fixture).prefix(8192)).write(to: file)
            #expect(throws: SnapshotReadError.self) { try SnapshotReader(fileURL: file) }
        }
    }

    @Test func anUnsupportedSchemaVersionIsRejected() throws {
        try SnapshotCopy.with("UPDATE meta SET value = '2' WHERE key = 'schema_version'") {
            file in
            #expect(throws: SnapshotReadError.unsupportedSchemaVersion(2)) {
                try SnapshotReader(fileURL: file)
            }
        }
    }

    @Test(arguments: SnapshotMeta.requiredKeys)
    func aMissingMetaKeyIsRejected(_ key: String) throws {
        try SnapshotCopy.with("DELETE FROM meta WHERE key = '\(key)'") { file in
            #expect(throws: SnapshotReadError.missingMetaKey(key)) {
                try SnapshotReader(fileURL: file)
            }
        }
    }

    @Test(arguments: [
        ("blend_patches", "[\"16.21\""),
        ("thresholds", "{\"champ_role\": [200]}"),
        ("priors", "{\"champ_role\": 100, \"relation\": 200, \"loadout\": 500}"),
        ("tier_cutoffs", "not json"),
        ("schema_version", "one"),
        ("queue", "ranked"),
        ("matches", "{}"),
        ("bracket", "master_plus"),
    ])
    func aMalformedMetaValueIsRejected(_ key: String, _ value: String) throws {
        try SnapshotCopy.with("UPDATE meta SET value = '\(value)' WHERE key = '\(key)'") { file in
            #expect(throws: SnapshotReadError.invalidMetaValue(key)) {
                try SnapshotReader(fileURL: file)
            }
        }
    }

    @Test func aRoleOutsideTheContractIsAMalformedTable() throws {
        try SnapshotCopy.with("UPDATE skill_orders SET role = 'MID' WHERE role = 'MIDDLE'") {
            file in
            #expect(throws: SnapshotReadError.malformedTable("skill_orders")) {
                try SnapshotReader(fileURL: file)
            }
        }
    }

    @Test func aMissingTableIsAMalformedTable() throws {
        try SnapshotCopy.with("DROP TABLE spell_pairs") { file in
            #expect(throws: SnapshotReadError.malformedTable("spell_pairs")) {
                try SnapshotReader(fileURL: file)
            }
        }
    }

    @Test func openingNeverWritesToTheFile() throws {
        try SnapshotCopy.with { file in
            let before = try Data(contentsOf: file)
            _ = try SnapshotReader(fileURL: file)
            #expect(try Data(contentsOf: file) == before)
            let siblings = try FileManager.default.contentsOfDirectory(
                atPath: file.deletingLastPathComponent().path(percentEncoded: false))
            #expect(siblings == ["emerald_plus.sqlite"])
        }
    }

    @Test func unknownMetaKeysAndSampleKindsAreIgnored() throws {
        try SnapshotCopy.with(
            """
            INSERT INTO meta VALUES ('future_key', '{}');
            UPDATE meta SET value = '{"champ_role":[200,1000],"future_kind":[1,2]}'
            WHERE key = 'thresholds';
            """
        ) { file in
            let meta = try #require(try SnapshotReader(fileURL: file).meta)
            #expect(
                meta.thresholds == [.championRole: SampleThreshold(minimum: 200, reliable: 1000)])
        }
    }

    // MARK: profile_rules

    @Test func aFileWithoutProfileRulesOpensWithNoRules() throws {
        try SnapshotCopy.with("DELETE FROM meta WHERE key = 'profile_rules'") { file in
            let meta = try #require(try SnapshotReader(fileURL: file).meta)
            #expect(meta.profileRules == nil)
            #expect(meta.matches == 20000)
        }
    }

    @Test(arguments: [
        "not json",
        "{\"min_champions\": 3}",
        """
        {"min_champions": 3, "heavy_ad": {"phys_share_weighted": 0.65},
         "heavy_ap": {"magic_share_weighted": 0.6}, "heavy_cc": {"cc_score_mean": 0.6},
         "mixed": {"not": "heavy_ad"}}
        """,
        """
        {"min_champions": "three", "heavy_ad": {"phys_share_weighted": 0.65},
         "heavy_ap": {"magic_share_weighted": 0.6}, "heavy_cc": {"cc_score_mean": 0.6},
         "mixed": {"not": ["heavy_ad", "heavy_ap"]}}
        """,
    ])
    func malformedProfileRulesAreRejected(_ value: String) throws {
        try SnapshotCopy.with(
            "UPDATE meta SET value = '\(value)' WHERE key = 'profile_rules'"
        ) { file in
            #expect(throws: SnapshotReadError.invalidMetaValue("profile_rules")) {
                try SnapshotReader(fileURL: file)
            }
        }
    }

    @Test func anUnknownProfileInMixedNotIsKeptAsUnknown() throws {
        try SnapshotCopy.with(
            """
            UPDATE meta SET value = '{"min_champions": 3,
                "heavy_ad": {"phys_share_weighted": 0.65},
                "heavy_ap": {"magic_share_weighted": 0.6}, "heavy_cc": {"cc_score_mean": 0.6},
                "mixed": {"not": ["heavy_ad", "heavy_tank"]}}'
            WHERE key = 'profile_rules'
            """
        ) { file in
            let rules = try #require(try SnapshotReader(fileURL: file).meta?.profileRules)
            #expect(rules.mixedExcludes == [.heavyAD, .unknown("heavy_tank")])
        }
    }

    // MARK: Tolerance

    @Test func anUnknownFlagIsKeptAsUnknown() throws {
        try SnapshotCopy.with("INSERT INTO champion_flags VALUES (103, 'split_push')") { file in
            let reader = try SnapshotReader(fileURL: file)
            #expect(reader.flags(of: ChampionID(rawValue: 103)) == [.unknown("split_push")])
        }
    }

    @Test func anUnknownEnemyProfileIsServedUnderItsRawValue() throws {
        try SnapshotCopy.with(
            """
            UPDATE champ_vs_profile SET enemy_profile = 'heavy_tank'
            WHERE champion_id = 103 AND enemy_profile = 'heavy_cc';
            UPDATE rune_page_vs_profile SET enemy_profile = 'heavy_tank'
            WHERE champion_id = 103 AND enemy_profile = 'heavy_cc';
            UPDATE item_vs_profile SET enemy_profile = 'heavy_tank'
            WHERE champion_id = 103 AND enemy_profile = 'heavy_cc';
            """
        ) { file in
            let reader = try SnapshotReader(fileURL: file)
            let ahri = ChampionID(rawValue: 103)
            let tank = EnemyProfile.unknown("heavy_tank")
            #expect(
                reader.profileStats(for: ahri, role: .middle, against: tank)
                    == RelationStats(games: 770, wins: 377))
            #expect(
                reader.runePages(for: ahri, role: .middle, against: tank).map(\.games)
                    == [482, 287])
            #expect(reader.finalItems(for: ahri, role: .middle, against: tank).count == 6)
            #expect(reader.profileStats(for: ahri, role: .middle, against: .heavyCC) == nil)
            #expect(
                reader.profileStats(for: ahri, role: .middle, against: .heavyAD)
                    == RelationStats(games: 797, wins: 433))
        }
    }

    /// §17: the diffs are NULL when a matchup has no timelines.
    @Test func aMatchupWithoutTimelinesHasNoDiffs() throws {
        try SnapshotCopy.with(
            """
            UPDATE matchup_stats SET tl_games = 0, gold_diff_15 = NULL, cs_diff_15 = NULL
            WHERE champion_id = 238 AND role = 'JUNGLE' AND opp_id = 64
            """
        ) { file in
            let reader = try SnapshotReader(fileURL: file)
            #expect(
                reader.matchup(for: Self.zed, role: .jungle, against: ChampionID(rawValue: 64))
                    == MatchupStats(
                        games: 443, wins: 242, timelineGames: 0, goldDiffAt15: nil,
                        csDiffAt15: nil))
        }
    }

    @Test func anAllyRoleOutsideTheContractIsAMalformedTable() throws {
        try SnapshotCopy.with(
            "UPDATE synergy_stats SET ally_role = 'SUPPORT' WHERE champion_id = 103 AND ally_id = 238"
        ) { file in
            #expect(throws: SnapshotReadError.malformedTable("synergy_stats")) {
                try SnapshotReader(fileURL: file)
            }
        }
    }

    @Test(arguments: [
        "matchup_stats", "synergy_stats", "vs_team_stats", "champion_profiles", "champ_vs_profile",
        "rune_page_vs_profile", "item_vs_profile", "champ_ban_stats", "champion_flags",
    ])
    func aMissingPhase7TableIsAMalformedTable(_ table: String) throws {
        try SnapshotCopy.with("DROP TABLE \(table)") { file in
            #expect(throws: SnapshotReadError.malformedTable(table)) {
                try SnapshotReader(fileURL: file)
            }
        }
    }

    // MARK: Lookups

    @Test func aChampionWithoutATimelineProfileHasZeroTimelineGames() throws {
        try SnapshotCopy.with(
            "DELETE FROM champion_profiles WHERE champion_id = 238 AND role = 'JUNGLE'"
        ) { file in
            let stats = try SnapshotReader(fileURL: file).championRoleStats(in: .jungle)
            #expect(
                stats[Self.zed]
                    == ChampionRoleStats(
                        games: 2746, wins: 1344, timelineGames: 0, kills: 10984, deaths: 13730,
                        assists: 21968, cs: 227918, minutes: 76888))
        }
    }

    @Test func anUnknownChampionHasNoData() throws {
        let reader = try SnapshotReader(fileURL: SnapshotCopy.fixture)
        let unknown = ChampionID(rawValue: 999_999)
        #expect(reader.roleGames(for: unknown).isEmpty)
        #expect(reader.runePages(for: unknown, role: .middle).isEmpty)
        #expect(reader.spellPairs(for: unknown, role: .middle).isEmpty)
        #expect(reader.itemBuilds(for: unknown, role: .middle).isEmpty)
        #expect(reader.skillOrders(for: unknown, role: .middle).isEmpty)
        #expect(reader.matchup(for: unknown, role: .middle, against: Self.zed) == nil)
        #expect(
            reader.synergy(for: unknown, role: .middle, with: Self.zed, allyRole: .jungle) == nil)
        #expect(reader.versusTeam(for: unknown, role: .middle, against: Self.zed) == nil)
        #expect(reader.championProfile(for: unknown, role: .middle) == nil)
        #expect(reader.profileStats(for: unknown, role: .middle, against: .mixed) == nil)
        #expect(reader.runePages(for: unknown, role: .middle, against: .mixed).isEmpty)
        #expect(reader.finalItems(for: unknown, role: .middle).isEmpty)
        #expect(reader.finalItems(for: unknown, role: .middle, against: .mixed).isEmpty)
        #expect(reader.bans(of: unknown) == nil)
        #expect(reader.flags(of: unknown).isEmpty)
    }

    @Test func aRoleTheChampionDoesNotPlayHasNoLoadouts() throws {
        let reader = try SnapshotReader(fileURL: SnapshotCopy.fixture)
        #expect(reader.runePages(for: Self.zed, role: .top).isEmpty)
        #expect(reader.spellPairs(for: Self.zed, role: .top).isEmpty)
        #expect(reader.itemBuilds(for: Self.zed, role: .top).isEmpty)
        #expect(reader.skillOrders(for: Self.zed, role: .top).isEmpty)
        #expect(reader.championRoleStats(in: .top)[Self.zed] == nil)
    }

    @Test func aRoleWithOnlyChampionRolesRowsHasNoStats() throws {
        let reader = try SnapshotReader(fileURL: SnapshotCopy.fixture)
        let darius = ChampionID(rawValue: 122)
        #expect(reader.roleGames(for: darius)[.jungle] == 25)
        #expect(reader.championRoleStats(in: .jungle)[darius] == nil)
        #expect(reader.runePages(for: darius, role: .jungle).isEmpty)
    }

    @Test func perOpponentRowsAreNeverReturned() throws {
        let reader = try SnapshotReader(fileURL: SnapshotCopy.fixture)
        #expect(reader.runePages(for: Self.zed, role: .jungle).map(\.games) == [2059, 687])
        #expect(reader.spellPairs(for: Self.zed, role: .jungle).map(\.games) == [2746])
        let ahri = ChampionID(rawValue: 103)
        #expect(
            reader.itemBuilds(for: ahri, role: .middle).filter { $0.layer == .start }
                .map(\.games) == [373])
    }

    @Test func spellPairsAreNormalizedEvenWhenStoredReversed() throws {
        try SnapshotCopy.with(
            """
            UPDATE spell_pairs SET spell_a = 11, spell_b = 4
            WHERE champion_id = 238 AND role = 'JUNGLE' AND opp_id = 0
            """
        ) { file in
            let pair = try #require(
                try SnapshotReader(fileURL: file).spellPairs(for: Self.zed, role: .jungle).first)
            #expect(pair.spellA == SummonerSpellID(rawValue: 4))
            #expect(pair.spellB == SummonerSpellID(rawValue: 11))
        }
    }
}
