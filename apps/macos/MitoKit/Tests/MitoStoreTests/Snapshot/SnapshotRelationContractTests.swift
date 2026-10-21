import MitoCore
import Testing

@testable import MitoStore

/// The §23.3 contract test for the Phase 7 tables: relations, enemy profiles, per-opponent and
/// per-profile loadouts, bans, flags, duration curves and item classes. Expected values come from
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
                    games: 518, wins: 263, timelineGames: 129, goldDiffAt15: -206.3,
                    csDiffAt15: 3.4))
    }

    /// §17 writes every relation in both orientations; the reader serves each row as written.
    @Test func aMatchupIsServedFromEachSidesOwnRow() throws {
        let reader = try Self.reader()
        #expect(
            reader.matchup(for: Self.zed, role: .middle, against: Self.ahri)
                == MatchupStats(
                    games: 518, wins: 255, timelineGames: 129, goldDiffAt15: 206.3,
                    csDiffAt15: -3.4))
        #expect(
            reader.matchup(for: Self.zed, role: .jungle, against: Self.leeSin)
                == MatchupStats(
                    games: 425, wins: 233, timelineGames: 5, goldDiffAt15: 219,
                    csDiffAt15: 4.1))
        #expect(
            reader.matchup(for: Self.leeSin, role: .jungle, against: Self.zed)
                == MatchupStats(
                    games: 425, wins: 192, timelineGames: 5, goldDiffAt15: -219,
                    csDiffAt15: -4.1))
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
                == RelationStats(games: 176, wins: 85))
        #expect(
            reader.synergy(for: Self.zed, role: .jungle, with: Self.lux, allyRole: .utility)
                == RelationStats(games: 285, wins: 140))
        #expect(reader.synergy(for: Self.zed, role: .jungle, with: Self.lux, allyRole: .top) == nil)
    }

    @Test func aSynergyIsServedFromEachSidesOwnRow() throws {
        let reader = try Self.reader()
        #expect(
            reader.synergy(for: Self.ahri, role: .middle, with: Self.zed, allyRole: .jungle)
                == RelationStats(games: 130, wins: 63))
        #expect(
            reader.synergy(for: Self.zed, role: .jungle, with: Self.ahri, allyRole: .middle)
                == RelationStats(games: 130, wins: 63))
    }

    @Test func versusTeamIsAgainstTheEnemyInAnyRole() throws {
        let reader = try Self.reader()
        #expect(
            reader.versusTeam(for: Self.ahri, role: .middle, against: Self.zed)
                == RelationStats(games: 610, wins: 308))
        #expect(
            reader.versusTeam(for: Self.zed, role: .jungle, against: Self.ahri)
                == RelationStats(games: 92, wins: 47))
        #expect(
            reader.versusTeam(for: Self.zed, role: .middle, against: Self.ahri)
                == RelationStats(games: 518, wins: 255))
        #expect(reader.versusTeam(for: Self.zed, role: .top, against: Self.ahri) == nil)
    }

    /// §17: A vs B summed over A's roles equals B vs A summed over B's roles, with complementary
    /// wins. Ahri plays only MIDDLE and Zed plays JUNGLE and MIDDLE, all of them exported.
    @Test func versusTeamAgreesAcrossBothOrientations() throws {
        let reader = try Self.reader()
        let ahriRoles = reader.roleGames(for: Self.ahri).keys
        let zedRoles = reader.roleGames(for: Self.zed).keys
        let ahriVersusZed = ahriRoles.compactMap {
            reader.versusTeam(for: Self.ahri, role: $0, against: Self.zed)
        }
        let zedVersusAhri = zedRoles.compactMap {
            reader.versusTeam(for: Self.zed, role: $0, against: Self.ahri)
        }
        #expect(ahriVersusZed.count == ahriRoles.count)
        #expect(zedVersusAhri.count == zedRoles.count)

        let ahriGames = ahriVersusZed.map(\.games).reduce(0, +)
        let zedGames = zedVersusAhri.map(\.games).reduce(0, +)
        let ahriWins = ahriVersusZed.map(\.wins).reduce(0, +)
        let zedWins = zedVersusAhri.map(\.wins).reduce(0, +)
        #expect(ahriGames == 610)
        #expect(zedGames == ahriGames)
        #expect(ahriWins + zedWins == ahriGames)
    }

    // MARK: Profiles

    @Test func aChampionProfileCarriesEveryColumn() throws {
        #expect(
            try Self.reader().championProfile(for: Self.ahri, role: .middle)
                == ChampionProfile(
                    physicalShare: 0.123, magicShare: 0.806, trueShare: 0.071,
                    damagePerMinute: 814.7, tankiness: 0.333, ccScore: 0.333, timelineGames: 706,
                    goldDiffAt15: -155.9, levelSixSeconds: 372, firstItemSeconds: 547,
                    secondItemSeconds: 938, thirdItemSeconds: 1431))
    }

    /// Zed JUNGLE has 40 timelines and no third-item sample: `item3_s` is NULL.
    @Test func aProfileWithoutATimelineSampleHasANilColumn() throws {
        let reader = try Self.reader()
        #expect(
            reader.championProfile(for: Self.zed, role: .jungle)
                == ChampionProfile(
                    physicalShare: 0.734, magicShare: 0.264, trueShare: 0.002,
                    damagePerMinute: 542.3, tankiness: 0.5, ccScore: 0, timelineGames: 40,
                    goldDiffAt15: 129.3, levelSixSeconds: 400, firstItemSeconds: 515,
                    secondItemSeconds: 873, thirdItemSeconds: nil))
        #expect(reader.championProfile(for: Self.zed, role: .top) == nil)
    }

    @Test func profileStatsAreTheGamesAgainstEachEnemyProfile() throws {
        let reader = try Self.reader()
        let expected: [EnemyProfile: RelationStats] = [
            .heavyAD: RelationStats(games: 752, wins: 365),
            .heavyAP: RelationStats(games: 680, wins: 318),
            .heavyCC: RelationStats(games: 771, wins: 394),
            .mixed: RelationStats(games: 1285, wins: 580),
        ]
        for (profile, stats) in expected {
            #expect(reader.profileStats(for: Self.ahri, role: .middle, against: profile) == stats)
        }
    }

    @Test func runePagesAgainstAProfileAreThatProfilesRowsMostPlayedFirst() throws {
        #expect(
            try Self.reader().runePages(for: Self.ahri, role: .middle, against: .heavyAD) == [
                RunePageCandidate(page: Self.page(1), games: 510, wins: 234),
                RunePageCandidate(page: Self.page(2), games: 236, wins: 128),
            ])
    }

    @Test func finalItemsWithoutAProfileAreTheAnyBaseline() throws {
        #expect(
            try Self.reader().finalItems(for: Self.ahri, role: .middle)
                == Self.items([
                    (3089, 2140, 1072), (3157, 2140, 1170), (6655, 2140, 1008), (3020, 1695, 844),
                    (3047, 339, 182), (3165, 226, 106),
                ]))
    }

    @Test func finalItemsAgainstAProfileAreThatProfilesRowsOnly() throws {
        #expect(
            try Self.reader().finalItems(for: Self.ahri, role: .middle, against: .heavyAD)
                == Self.items([
                    (3157, 752, 426), (3089, 570, 276), (6655, 570, 305), (3020, 452, 221),
                    (3047, 271, 156), (3165, 61, 28),
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

    /// Ahri MIDDLE vs Zed has two pages tied at 207 games; the lower `page_id` comes first.
    @Test func perOpponentRunePagesAreTheRowsForThatOpponent() throws {
        #expect(
            try Self.reader().runePages(for: Self.ahri, role: .middle, against: Self.zed) == [
                RunePageCandidate(page: Self.page(1), games: 207, wins: 99),
                RunePageCandidate(page: Self.page(2), games: 207, wins: 112),
            ])
    }

    @Test func perOpponentSpellPairsAreTheRowsForThatOpponent() throws {
        #expect(
            try Self.reader().spellPairs(for: Self.ahri, role: .middle, against: Self.zed) == [
                SpellPairCandidate(
                    spellA: SummonerSpellID(rawValue: 4), spellB: SummonerSpellID(rawValue: 14),
                    games: 259, wins: 130)
            ])
    }

    @Test func perOpponentItemBuildsAreTheRowsForThatOpponent() throws {
        #expect(
            try Self.reader().itemBuilds(for: Self.ahri, role: .middle, against: Self.zed) == [
                ItemBuildCandidate(
                    layer: .core, items: [6655, 3157, 3089].map(ItemID.init(rawValue:)),
                    games: 129, wins: 64),
                ItemBuildCandidate(
                    layer: .start, items: [1056, 2003, 2003].map(ItemID.init(rawValue:)),
                    games: 129, wins: 61),
                ItemBuildCandidate(
                    layer: .boots, items: [ItemID(rawValue: 3020)], games: 103, wins: 48),
            ])
    }

    @Test func generalLoadoutsNeverIncludePerOpponentRows() throws {
        let reader = try Self.reader()
        #expect(reader.runePages(for: Self.ahri, role: .middle).map(\.games) == [2118, 706])
        #expect(reader.spellPairs(for: Self.zed, role: .middle).map(\.games) == [1428, 767])
        #expect(
            reader.itemBuilds(for: Self.zed, role: .middle).filter { $0.layer == .start }
                .map(\.games) == [402])
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
                == [212])
        #expect(
            reader.spellPairs(for: Self.zed, role: .jungle, against: Self.leeSin).map(\.games)
                == [212])
        #expect(reader.itemBuilds(for: Self.zed, role: .jungle, against: Self.leeSin).isEmpty)
    }

    // MARK: Bans and flags

    @Test func bansAreTheMatchesInWhichTheChampionWasBanned() throws {
        let reader = try Self.reader()
        #expect(reader.bans(of: ChampionID(rawValue: 86)) == 2261)
        #expect(reader.bans(of: Self.ahri) == 2646)
        #expect(reader.bans(of: ChampionID(rawValue: 999_999)) == nil)
    }

    @Test func flagsAreTheCuratedSetOfTheChampion() throws {
        let reader = try Self.reader()
        #expect(reader.flags(of: Self.ashe) == [.autoAttacker, .engage])
        #expect(reader.flags(of: Self.lux) == [.poke])
        #expect(reader.flags(of: Self.ahri).isEmpty)
    }

    // MARK: Duration curves

    @Test func aDurationCurveHasEveryBucketOfItsChampionAndRole() throws {
        #expect(
            try Self.reader().durationCurves(for: Self.ahri, role: .middle) == [
                .under20: RelationStats(games: 214, wins: 101),
                .from20To25: RelationStats(games: 312, wins: 153),
                .from25To30: RelationStats(games: 1439, wins: 734),
                .from30To35: RelationStats(games: 158, wins: 70),
                .from35To40: RelationStats(games: 2, wins: 0),
                .over40: RelationStats(games: 699, wins: 362),
            ])
    }

    /// Zed plays JUNGLE and MIDDLE; each role is its own curve.
    @Test func aDurationCurveIsKeyedByRole() throws {
        let reader = try Self.reader()
        #expect(
            reader.durationCurves(for: Self.zed, role: .jungle)[.under20]
                == RelationStats(games: 210, wins: 90))
        #expect(
            reader.durationCurves(for: Self.zed, role: .middle)[.under20]
                == RelationStats(games: 947, wins: 478))
        #expect(reader.durationCurves(for: Self.zed, role: .top).isEmpty)
    }

    /// §17: a champion's buckets split its games and its wins, so both sum to `champ_role_stats`.
    @Test func aDurationCurveSumsToItsChampionRoleStats() throws {
        let reader = try Self.reader()
        let curve = reader.durationCurves(for: Self.ahri, role: .middle).values
        let stats = try #require(reader.championRoleStats(in: .middle)[Self.ahri])
        #expect(curve.map(\.games).reduce(0, +) == stats.games)
        #expect(curve.map(\.wins).reduce(0, +) == stats.wins)
    }

    // MARK: Item classes

    @Test(arguments: [
        (1001, ItemClass.bootsT1), (1036, .component), (1056, .starter), (2003, .consumable),
        (3047, .bootsT2), (3157, .legendary), (3869, .supportUpgrade),
    ])
    func anItemCarriesItsSnapshotClass(item: Int, itemClass: ItemClass) throws {
        #expect(try Self.reader().itemClass(of: ItemID(rawValue: item)) == itemClass)
    }

    @Test func antihealIsTheFlaggedItemsOnly() throws {
        let reader = try Self.reader()
        #expect([3033, 3075, 3165].allSatisfy { reader.isAntiheal(ItemID(rawValue: $0)) })
        #expect(!reader.isAntiheal(ItemID(rawValue: 3157)))
    }

    /// 6609 is antiheal in the game but absent from the fixture's `item_classes`.
    @Test func anUnclassifiedItemHasNoClassAndIsNotAntiheal() throws {
        let reader = try Self.reader()
        #expect(reader.itemClass(of: ItemID(rawValue: 6609)) == nil)
        #expect(!reader.isAntiheal(ItemID(rawValue: 6609)))
    }
}
