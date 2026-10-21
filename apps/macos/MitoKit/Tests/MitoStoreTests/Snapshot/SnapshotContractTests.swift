import Foundation
import GRDB
import MitoCore
import Testing

@testable import MitoStore

/// The §23.3 contract test: the mito-data fixture, read by the shipped reader. Expected values
/// come from `sqlite3 fixtures/snapshot/emerald_plus.sqlite`; a regenerated fixture that moves
/// them is a contract change to review, not a number to bump.
struct SnapshotContractTests {
    private static let zed = ChampionID(rawValue: 238)
    private static let ahri = ChampionID(rawValue: 103)
    private static let udyr = ChampionID(rawValue: 77)

    private static func reader() throws -> SnapshotReader {
        try SnapshotReader(fileURL: SnapshotCopy.fixture)
    }

    @Test func theFixtureDeclaresASupportedSchemaVersion() throws {
        var configuration = Configuration()
        configuration.readonly = true
        let queue = try DatabaseQueue(
            path: SnapshotCopy.fixture.path(percentEncoded: false), configuration: configuration)
        let version = try queue.read {
            try String.fetchOne($0, sql: "SELECT value FROM meta WHERE key = 'schema_version'")
        }
        #expect(version == "1")
        #expect(SnapshotReader.supportedSchemaVersions.contains(1))
    }

    @Test func metaCarriesTheFileIdentityAndMatchCount() throws {
        let meta = try #require(try Self.reader().meta)
        #expect(meta.patch == Patch(rawValue: "16.21"))
        #expect(meta.queue == QueueID(rawValue: 420))
        #expect(meta.bracket == .emeraldPlus)
        #expect(meta.matches == 20000)
        #expect(meta.blendPatches == [Patch(rawValue: "16.21")])
    }

    @Test func metaThresholdsCoverEverySampleKind() throws {
        let meta = try #require(try Self.reader().meta)
        #expect(
            meta.thresholds == [
                .championRole: SampleThreshold(minimum: 200, reliable: 1000),
                .matchup: SampleThreshold(minimum: 30, reliable: 300),
                .synergy: SampleThreshold(minimum: 50, reliable: 400),
                .vsTeam: SampleThreshold(minimum: 30, reliable: 300),
                .profile: SampleThreshold(minimum: 100, reliable: 500),
                .runePage: SampleThreshold(minimum: 100, reliable: 800),
                .buildLayer: SampleThreshold(minimum: 100, reliable: 600),
                .itemVsProfile: SampleThreshold(minimum: 50, reliable: 300),
                .spells: SampleThreshold(minimum: 100, reliable: 500),
                .skillOrder: SampleThreshold(minimum: 100, reliable: 600),
            ])
    }

    @Test func metaPriorsAndTierCutoffsMatchTheFile() throws {
        let meta = try #require(try Self.reader().meta)
        #expect(
            meta.priors
                == SmoothingPriors(
                    championRoleStrength: 100, championRoleBaseline: 0.5, relationStrength: 200,
                    loadoutStrength: 500))
        #expect(meta.tierCutoffs == [.s: 0.53, .a: 0.515, .b: 0.5, .c: 0.485])
    }

    @Test func roleGamesListEveryRoleOfTheChampion() throws {
        let reader = try Self.reader()
        #expect(reader.roleGames(for: Self.zed) == [.jungle: 2746, .middle: 2195])
        #expect(reader.roleGames(for: ChampionID(rawValue: 122)) == [.top: 3378, .jungle: 25])
    }

    @Test func championRoleStatsCarryTheSumsAndJoinTheTimelineGames() throws {
        let stats = try Self.reader().championRoleStats(in: .jungle)
        #expect(
            stats == [
                ChampionID(rawValue: 64): ChampionRoleStats(
                    games: 3600, wins: 1796, timelineGames: 900, kills: 28800, deaths: 18000,
                    assists: 39600, cs: 392400, minutes: 100800),
                Self.udyr: ChampionRoleStats(
                    games: 2558, wins: 1157, timelineGames: 639, kills: 17906, deaths: 7674,
                    assists: 10232, cs: 544854, minutes: 74182),
                Self.zed: ChampionRoleStats(
                    games: 2746, wins: 1344, timelineGames: 40, kills: 10984, deaths: 13730,
                    assists: 21968, cs: 227918, minutes: 76888),
            ])
    }

    @Test func runePagesAreTheGeneralRowsResolvedInLCUOrder() throws {
        let pages = try Self.reader().runePages(for: Self.ahri, role: .middle)
        #expect(
            pages == [
                RunePageCandidate(
                    page: RunePage(
                        primaryStyle: PerkStyleID(rawValue: 8100),
                        subStyle: PerkStyleID(rawValue: 8300),
                        perks: [8112, 8143, 8140, 8135, 8345, 8347, 5008, 5008, 5011].map(
                            PerkID.init(rawValue:))),
                    games: 2118, wins: 1093),
                RunePageCandidate(
                    page: RunePage(
                        primaryStyle: PerkStyleID(rawValue: 8200),
                        subStyle: PerkStyleID(rawValue: 8300),
                        perks: [8229, 8226, 8210, 8237, 8304, 8347, 5007, 5008, 5011].map(
                            PerkID.init(rawValue:))),
                    games: 706, wins: 336),
            ])
    }

    @Test func spellPairsAreTheGeneralRowsMostPlayedFirst() throws {
        let pairs = try Self.reader().spellPairs(for: Self.ahri, role: .middle)
        #expect(
            pairs == [
                SpellPairCandidate(
                    spellA: SummonerSpellID(rawValue: 4), spellB: SummonerSpellID(rawValue: 14),
                    games: 2650, wins: 1325),
                SpellPairCandidate(
                    spellA: SummonerSpellID(rawValue: 4), spellB: SummonerSpellID(rawValue: 12),
                    games: 174, wins: 80),
            ])
    }

    @Test func itemBuildsAreTheGeneralRowsWithEmptySlotsDropped() throws {
        let builds = try Self.reader().itemBuilds(for: Self.ahri, role: .middle)
        func build(_ layer: BuildLayer, _ items: [Int], _ games: Int, _ wins: Int)
            -> ItemBuildCandidate
        {
            ItemBuildCandidate(
                layer: layer, items: items.map(ItemID.init(rawValue:)), games: games, wins: wins)
        }
        #expect(
            builds == [
                build(.boots, [3020], 688, 354),
                build(.sixth, [3046], 650, 341),
                build(.fifth, [3033], 415, 225),
                build(.start, [1056, 2003, 2003], 373, 188),
                build(.fourth, [3031], 305, 148),
                build(.core, [6655, 3157, 3089], 303, 152),
            ])
    }

    @Test func skillOrdersCarryTheMaxOrderAndItsSequence() throws {
        let orders = try Self.reader().skillOrders(for: Self.ahri, role: .middle)
        #expect(
            orders == [
                SkillOrderCandidate(
                    order: SkillOrder(
                        maxOrder: [.q, .w, .e], sequence: Self.abilities("QWEQQRQQWWRWWEEREE")),
                    games: 706, wins: 338)
            ])
    }

    /// §17: a kit that levels R as a basic has a 4-letter `max_order` (Udyr JUNGLE).
    @Test func aKitThatLevelsRAsABasicHasAFourLetterMaxOrder() throws {
        let orders = try Self.reader().skillOrders(for: Self.udyr, role: .jungle)
        #expect(
            orders == [
                SkillOrderCandidate(
                    order: SkillOrder(
                        maxOrder: [.r, .q, .w, .e],
                        sequence: Self.abilities("RQWERRRRQQQQWWWWEE")),
                    games: 497, wins: 229),
                SkillOrderCandidate(
                    order: SkillOrder(
                        maxOrder: [.q, .r, .w, .e],
                        sequence: Self.abilities("QRWEQQQQRRRRWWWWEE")),
                    games: 142, wins: 74),
            ])
    }

    /// §14.12: when no row passes a minimum only the most played one is exported, so Zed
    /// JUNGLE keeps a single skill order under `skill_order`.
    @Test func aLoadoutUnderItsMinimumKeepsOnlyTheMostPlayedRow() throws {
        let reader = try Self.reader()
        let minimum = try #require(reader.meta?.thresholds[.skillOrder]).minimum
        let orders = reader.skillOrders(for: Self.zed, role: .jungle)
        #expect(
            orders == [
                SkillOrderCandidate(
                    order: SkillOrder(
                        maxOrder: [.q, .e, .w], sequence: Self.abilities("QEWQQRQQEEREEWWRWW")),
                    games: 40, wins: 20)
            ])
        #expect(orders.allSatisfy { $0.games < minimum })
    }

    /// §14.12: Zed JUNGLE has too few timelines for `build_layer`, so its core and boots come
    /// from final items with the match denominator, and they are still present.
    @Test func aChampionBelowTheBuildLayerMinimumStillHasCoreAndBoots() throws {
        let reader = try Self.reader()
        let meta = try #require(reader.meta)
        let minimum = try #require(meta.thresholds[.buildLayer]).minimum
        let stats = try #require(reader.championRoleStats(in: .jungle)[Self.zed])
        #expect(stats.timelineGames < minimum)

        let builds = reader.itemBuilds(for: Self.zed, role: .jungle)
        let core = builds.filter { $0.layer == .core }
        let boots = builds.filter { $0.layer == .boots }
        #expect(core.map(\.items) == [[3142, 6692, 3071].map(ItemID.init(rawValue:))])
        #expect(boots.map(\.items) == [[ItemID(rawValue: 3158)]])
        #expect(core.allSatisfy { $0.games > stats.timelineGames && $0.games <= stats.games })
        #expect(boots.allSatisfy { $0.games > stats.timelineGames && $0.games <= stats.games })
    }

    /// §14.12: the fallback covers only core and boots. Zed JUNGLE's start comes from its 40
    /// timelines, and it has no 4th–6th item rows.
    @Test func aChampionBelowTheBuildLayerMinimumTakesTheRestFromTimelinesOnly() throws {
        let reader = try Self.reader()
        let stats = try #require(reader.championRoleStats(in: .jungle)[Self.zed])
        let builds = reader.itemBuilds(for: Self.zed, role: .jungle)

        let start = builds.filter { $0.layer == .start }
        #expect(
            start == [
                ItemBuildCandidate(
                    layer: .start, items: [ItemID(rawValue: 1101)], games: 26, wins: 14)
            ])
        #expect(start.allSatisfy { $0.games <= stats.timelineGames })
        #expect(builds.allSatisfy { ![.fourth, .fifth, .sixth].contains($0.layer) })
    }

    private static func abilities(_ letters: String) -> [SkillOrder.Ability] {
        letters.compactMap { SkillOrder.Ability(rawValue: String($0)) }
    }
}
