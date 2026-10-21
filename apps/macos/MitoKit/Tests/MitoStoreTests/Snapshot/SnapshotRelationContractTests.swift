import MitoCore
import Testing

@testable import MitoStore

/// The §23.3 contract test for the Phase 7 tables: relations, enemy profiles, per-opponent and
/// per-profile loadouts, bans and flags. Expected values come from
/// `sqlite3 fixtures/snapshot/emerald_plus.sqlite`.
struct SnapshotRelationContractTests {
    private static let zed = ChampionID(rawValue: 238)
    private static let ahri = ChampionID(rawValue: 103)
    private static let lux = ChampionID(rawValue: 99)
    private static let ashe = ChampionID(rawValue: 22)
    private static let leeSin = ChampionID(rawValue: 64)

    private static func reader() throws -> SnapshotReader {
        try SnapshotReader(fileURL: SnapshotCopy.fixture)
    }

    private static func page(_ id: Int) -> RunePage {
        switch id {
        case 1:
            RunePage(
                primaryStyle: PerkStyleID(rawValue: 8100), subStyle: PerkStyleID(rawValue: 8300),
                perks: [8112, 8143, 8140, 8135, 8345, 8347, 5008, 5008, 5011].map(
                    PerkID.init(rawValue:)))
        default:
            RunePage(
                primaryStyle: PerkStyleID(rawValue: 8200), subStyle: PerkStyleID(rawValue: 8300),
                perks: [8229, 8226, 8210, 8237, 8304, 8347, 5007, 5008, 5011].map(
                    PerkID.init(rawValue:)))
        }
    }

    private static func items(_ rows: [(Int, Int, Int)]) -> [FinalItemCandidate] {
        rows.map { FinalItemCandidate(item: ItemID(rawValue: $0.0), games: $0.1, wins: $0.2) }
    }

    // MARK: meta

    @Test func metaCarriesTheCalibratedProfileRules() throws {
        let meta = try #require(try Self.reader().meta)
        #expect(
            meta.profileRules
                == ProfileRules(
                    minimumChampions: 3, heavyADPhysicalShare: 0.65, heavyAPMagicShare: 0.6,
                    heavyCCScore: 0.6, mixedExcludes: [.heavyAD, .heavyAP]))
    }

    // MARK: Relations

    @Test func aMatchupCarriesItsCountsAndTimelineDiffs() throws {
        #expect(
            try Self.reader().matchup(for: Self.ahri, role: .middle, against: Self.zed)
                == MatchupStats(
                    games: 497, wins: 237, timelineGames: 124, goldDiffAt15: -309.3,
                    csDiffAt15: -5.9))
    }

    /// §17 writes every relation in both orientations; the reader serves each row as written.
    @Test func aMatchupIsServedFromEachSidesOwnRow() throws {
        let reader = try Self.reader()
        #expect(
            reader.matchup(for: Self.zed, role: .middle, against: Self.ahri)
                == MatchupStats(
                    games: 497, wins: 260, timelineGames: 124, goldDiffAt15: 309.3,
                    csDiffAt15: 5.9))
        #expect(
            reader.matchup(for: Self.zed, role: .jungle, against: Self.leeSin)
                == MatchupStats(
                    games: 518, wins: 254, timelineGames: 5, goldDiffAt15: 218.2,
                    csDiffAt15: 0.8))
        #expect(
            reader.matchup(for: Self.leeSin, role: .jungle, against: Self.zed)
                == MatchupStats(
                    games: 518, wins: 264, timelineGames: 5, goldDiffAt15: -218.2,
                    csDiffAt15: -0.8))
    }

    @Test func aMatchupWithoutARowIsNil() throws {
        let reader = try Self.reader()
        #expect(reader.matchup(for: Self.ahri, role: .middle, against: Self.ashe) == nil)
        #expect(reader.matchup(for: Self.zed, role: .jungle, against: Self.ahri) == nil)
    }

    @Test func aSynergyIsKeyedByTheAllysRole() throws {
        let reader = try Self.reader()
        #expect(
            reader.synergy(for: Self.zed, role: .jungle, with: Self.lux, allyRole: .middle)
                == RelationStats(games: 175, wins: 89))
        #expect(
            reader.synergy(for: Self.zed, role: .jungle, with: Self.lux, allyRole: .utility)
                == RelationStats(games: 184, wins: 93))
        #expect(reader.synergy(for: Self.zed, role: .jungle, with: Self.lux, allyRole: .top) == nil)
    }

    @Test func aSynergyIsServedFromEachSidesOwnRow() throws {
        let reader = try Self.reader()
        #expect(
            reader.synergy(for: Self.ahri, role: .middle, with: Self.zed, allyRole: .jungle)
                == RelationStats(games: 180, wins: 90))
        #expect(
            reader.synergy(for: Self.zed, role: .jungle, with: Self.ahri, allyRole: .middle)
                == RelationStats(games: 180, wins: 90))
    }

    @Test func versusTeamIsAgainstTheEnemyInAnyRole() throws {
        let reader = try Self.reader()
        #expect(
            reader.versusTeam(for: Self.ahri, role: .middle, against: Self.zed)
                == RelationStats(games: 661, wins: 307))
        #expect(
            reader.versusTeam(for: Self.zed, role: .jungle, against: Self.ahri)
                == RelationStats(games: 201, wins: 103))
        #expect(
            reader.versusTeam(for: Self.zed, role: .middle, against: Self.ahri)
                == RelationStats(games: 574, wins: 314))
        #expect(reader.versusTeam(for: Self.zed, role: .top, against: Self.ahri) == nil)
    }

    // MARK: Profiles

    @Test func aChampionProfileCarriesEveryColumn() throws {
        #expect(
            try Self.reader().championProfile(for: Self.ahri, role: .middle)
                == ChampionProfile(
                    physicalShare: 0.157, magicShare: 0.834, trueShare: 0.009,
                    damagePerMinute: 771.2, tankiness: 0.333, ccScore: 0.333, timelineGames: 706,
                    goldDiffAt15: 163.1, levelSixSeconds: 367, firstItemSeconds: 636,
                    secondItemSeconds: 1025, thirdItemSeconds: 1322))
    }

    /// Zed JUNGLE has 40 timelines and no third-item sample: `item3_s` is NULL.
    @Test func aProfileWithoutATimelineSampleHasANilColumn() throws {
        let reader = try Self.reader()
        #expect(
            reader.championProfile(for: Self.zed, role: .jungle)
                == ChampionProfile(
                    physicalShare: 0.718, magicShare: 0.27, trueShare: 0.012,
                    damagePerMinute: 813.4, tankiness: 0.5, ccScore: 0, timelineGames: 40,
                    goldDiffAt15: 103.7, levelSixSeconds: 411, firstItemSeconds: 555,
                    secondItemSeconds: 903, thirdItemSeconds: nil))
        #expect(reader.championProfile(for: Self.zed, role: .top) == nil)
    }

    @Test func profileStatsAreTheGamesAgainstEachEnemyProfile() throws {
        let reader = try Self.reader()
        let expected: [EnemyProfile: RelationStats] = [
            .heavyAD: RelationStats(games: 614, wins: 306),
            .heavyAP: RelationStats(games: 662, wins: 345),
            .heavyCC: RelationStats(games: 698, wins: 349),
            .mixed: RelationStats(games: 1187, wins: 615),
        ]
        for (profile, stats) in expected {
            #expect(reader.profileStats(for: Self.ahri, role: .middle, against: profile) == stats)
        }
    }

    @Test func runePagesAgainstAProfileAreThatProfilesRowsMostPlayedFirst() throws {
        #expect(
            try Self.reader().runePages(for: Self.ahri, role: .middle, against: .heavyAD) == [
                RunePageCandidate(page: Self.page(1), games: 449, wins: 235),
                RunePageCandidate(page: Self.page(2), games: 159, wins: 86),
            ])
    }

    @Test func finalItemsWithoutAProfileAreTheAnyBaseline() throws {
        #expect(
            try Self.reader().finalItems(for: Self.ahri, role: .middle)
                == Self.items([
                    (3089, 1959, 1053), (3020, 1694, 804), (6655, 1693, 789), (3047, 339, 178),
                    (3157, 226, 103), (3165, 226, 119),
                ]))
    }

    @Test func finalItemsAgainstAProfileAreThatProfilesRowsOnly() throws {
        #expect(
            try Self.reader().finalItems(for: Self.ahri, role: .middle, against: .heavyAD)
                == Self.items([
                    (3089, 426, 224), (3020, 368, 177), (6655, 368, 176), (3047, 221, 128),
                    (3157, 123, 63),
                ]))
    }

    /// `'any'` is the situational baseline, not a profile (§17, §18.7).
    @Test func anyIsNotAnEnemyProfile() throws {
        let reader = try Self.reader()
        let any = EnemyProfile(rawValue: "any")
        #expect(reader.finalItems(for: Self.ahri, role: .middle, against: any).isEmpty)
        #expect(reader.runePages(for: Self.ahri, role: .middle, against: any).isEmpty)
        #expect(reader.profileStats(for: Self.ahri, role: .middle, against: any) == nil)
    }

    // MARK: Per opponent

    /// Ahri MIDDLE vs Zed has two pages tied at 198 games; the lower `page_id` comes first.
    @Test func perOpponentRunePagesAreTheRowsForThatOpponent() throws {
        #expect(
            try Self.reader().runePages(for: Self.ahri, role: .middle, against: Self.zed) == [
                RunePageCandidate(page: Self.page(1), games: 198, wins: 95),
                RunePageCandidate(page: Self.page(2), games: 198, wins: 107),
            ])
    }

    @Test func perOpponentSpellPairsAreTheRowsForThatOpponent() throws {
        #expect(
            try Self.reader().spellPairs(for: Self.ahri, role: .middle, against: Self.zed) == [
                SpellPairCandidate(
                    spellA: SummonerSpellID(rawValue: 4), spellB: SummonerSpellID(rawValue: 14),
                    games: 248, wins: 121)
            ])
    }

    @Test func perOpponentItemBuildsAreTheRowsForThatOpponent() throws {
        #expect(
            try Self.reader().itemBuilds(for: Self.ahri, role: .middle, against: Self.zed) == [
                ItemBuildCandidate(
                    layer: .start, items: [1056, 2003, 2003].map(ItemID.init(rawValue:)),
                    games: 124, wins: 63),
                ItemBuildCandidate(
                    layer: .core, items: [6655, 3157, 3089].map(ItemID.init(rawValue:)),
                    games: 106, wins: 48),
                ItemBuildCandidate(
                    layer: .boots, items: [ItemID(rawValue: 3020)], games: 101, wins: 46),
            ])
    }

    @Test func generalLoadoutsNeverIncludePerOpponentRows() throws {
        let reader = try Self.reader()
        #expect(reader.runePages(for: Self.ahri, role: .middle).map(\.games) == [2118, 706])
        #expect(reader.spellPairs(for: Self.zed, role: .middle).map(\.games) == [1117, 1078])
        #expect(
            reader.itemBuilds(for: Self.zed, role: .middle).filter { $0.layer == .start }
                .map(\.games) == [422])
    }

    @Test func perOpponentLoadoutsNeverFallBackToTheGeneralRows() throws {
        let reader = try Self.reader()
        let general = ChampionID(rawValue: 0)
        #expect(reader.runePages(for: Self.ahri, role: .middle, against: general).isEmpty)
        #expect(reader.spellPairs(for: Self.ahri, role: .middle, against: general).isEmpty)
        #expect(reader.itemBuilds(for: Self.ahri, role: .middle, against: general).isEmpty)
        #expect(reader.runePages(for: Self.ahri, role: .middle, against: Self.ashe).isEmpty)
        #expect(reader.spellPairs(for: Self.ahri, role: .middle, against: Self.ashe).isEmpty)
        #expect(reader.itemBuilds(for: Self.ahri, role: .middle, against: Self.ashe).isEmpty)
    }

    /// Zed JUNGLE vs Lee Sin has 5 timelines, so the export kept its runes and spells but no
    /// item layers; the general builds must not stand in for them.
    @Test func aPerOpponentLayerTheExportDroppedIsEmpty() throws {
        let reader = try Self.reader()
        #expect(
            reader.runePages(for: Self.zed, role: .jungle, against: Self.leeSin).map(\.games)
                == [259])
        #expect(
            reader.spellPairs(for: Self.zed, role: .jungle, against: Self.leeSin).map(\.games)
                == [259])
        #expect(reader.itemBuilds(for: Self.zed, role: .jungle, against: Self.leeSin).isEmpty)
    }

    // MARK: Bans and flags

    @Test func bansAreTheMatchesInWhichTheChampionWasBanned() throws {
        let reader = try Self.reader()
        #expect(reader.bans(of: ChampionID(rawValue: 86)) == 3758)
        #expect(reader.bans(of: Self.ahri) == 996)
        #expect(reader.bans(of: ChampionID(rawValue: 999_999)) == nil)
    }

    @Test func flagsAreTheCuratedSetOfTheChampion() throws {
        let reader = try Self.reader()
        #expect(reader.flags(of: Self.ashe) == [.autoAttacker, .engage])
        #expect(reader.flags(of: Self.lux) == [.poke])
        #expect(reader.flags(of: Self.ahri).isEmpty)
    }
}
