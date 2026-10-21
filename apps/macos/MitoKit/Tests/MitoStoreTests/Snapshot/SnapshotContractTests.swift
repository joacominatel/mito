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
        #expect(reader.roleGames(for: Self.zed) == [.jungle: 2249, .middle: 1067])
        #expect(reader.roleGames(for: ChampionID(rawValue: 122)) == [.top: 2092, .jungle: 25])
    }

    @Test func championRoleStatsJoinTheTimelineGames() throws {
        let stats = try Self.reader().championRoleStats(in: .jungle)
        #expect(
            stats == [
                ChampionID(rawValue: 64): ChampionRoleStats(
                    games: 1716, wins: 820, timelineGames: 429),
                Self.zed: ChampionRoleStats(games: 2249, wins: 1062, timelineGames: 40),
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
                        perks: [8112, 8143, 8138, 8135, 8345, 8347, 5008, 5008, 5011].map(
                            PerkID.init(rawValue:))),
                    games: 743, wins: 336),
                RunePageCandidate(
                    page: RunePage(
                        primaryStyle: PerkStyleID(rawValue: 8200),
                        subStyle: PerkStyleID(rawValue: 8300),
                        perks: [8229, 8226, 8210, 8237, 8304, 8347, 5007, 5008, 5011].map(
                            PerkID.init(rawValue:))),
                    games: 248, wins: 134),
            ])
    }

    @Test func spellPairsAreTheGeneralRowsMostPlayedFirst() throws {
        let pairs = try Self.reader().spellPairs(for: Self.ahri, role: .middle)
        #expect(
            pairs == [
                SpellPairCandidate(
                    spellA: SummonerSpellID(rawValue: 4), spellB: SummonerSpellID(rawValue: 14),
                    games: 690, wins: 379),
                SpellPairCandidate(
                    spellA: SummonerSpellID(rawValue: 4), spellB: SummonerSpellID(rawValue: 12),
                    games: 301, wins: 161),
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
                build(.start, [1056, 2003, 2003], 223, 101),
                build(.fifth, [3033], 208, 111),
                build(.core, [6655, 3157, 3089], 189, 85),
                build(.fourth, [3031], 186, 96),
                build(.sixth, [3046], 136, 63),
                build(.boots, [3020], 133, 65),
            ])
    }

    @Test func skillOrdersCarryTheMaxOrderAndItsSequence() throws {
        let orders = try Self.reader().skillOrders(for: Self.zed, role: .jungle)
        #expect(
            orders == [
                SkillOrderCandidate(
                    order: SkillOrder(
                        maxOrder: [.q, .e, .w], sequence: Self.abilities("QEWQQRQQEEREEWWRWW")),
                    games: 28, wins: 14),
                SkillOrderCandidate(
                    order: SkillOrder(
                        maxOrder: [.q, .w, .e], sequence: Self.abilities("QWEQQRQQWWRWWEEREE")),
                    games: 12, wins: 6),
            ])
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

    private static func abilities(_ letters: String) -> [SkillOrder.Ability] {
        letters.compactMap { SkillOrder.Ability(rawValue: String($0)) }
    }
}
