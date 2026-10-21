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

    // MARK: Lookups

    @Test func aChampionWithoutATimelineProfileHasZeroTimelineGames() throws {
        try SnapshotCopy.with(
            "DELETE FROM champion_profiles WHERE champion_id = 238 AND role = 'JUNGLE'"
        ) { file in
            let stats = try SnapshotReader(fileURL: file).championRoleStats(in: .jungle)
            #expect(
                stats[Self.zed]
                    == ChampionRoleStats(
                        games: 2746, wins: 1340, timelineGames: 0, kills: 8238, deaths: 10984,
                        assists: 19222, cs: 329520, minutes: 79634))
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
                .map(\.games) == [572])
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
