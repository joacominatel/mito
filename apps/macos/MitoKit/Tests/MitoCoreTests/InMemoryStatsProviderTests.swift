import MitoCore
import MitoTestSupport
import Testing

struct InMemoryStatsProviderTests {
    private let ahri = ChampionID(rawValue: 103)

    @Test func servesTheGivenRoleGames() {
        let stats = InMemoryStatsProvider(roleGamesByChampion: [ahri: [.middle: 900, .top: 12]])
        #expect(stats.roleGames(for: ahri) == [.middle: 900, .top: 12])
    }

    @Test func aChampionWithoutRowsHasNoRoleGames() {
        #expect(InMemoryStatsProvider().roleGames(for: ChampionID(rawValue: 950)).isEmpty)
    }

    @Test func servesTheGivenMeta() {
        let meta = SnapshotMeta(
            patch: Patch(rawValue: "16.21"),
            queue: QueueID(rawValue: 420),
            bracket: .emeraldPlus,
            matches: 20_000,
            blendPatches: [Patch(rawValue: "16.21")],
            thresholds: [.championRole: SampleThreshold(minimum: 200, reliable: 1_000)],
            priors: SmoothingPriors(
                championRoleStrength: 100, championRoleBaseline: 0.5, relationStrength: 200,
                loadoutStrength: 500),
            tierCutoffs: [.s: 0.53, .a: 0.515, .b: 0.5, .c: 0.485])
        #expect(InMemoryStatsProvider(meta: meta).meta == meta)
    }

    @Test func servesChampionRoleStatsOnlyForTheirRole() {
        let row = ChampionRoleStats(games: 1_933, wins: 1_053, timelineGames: 483)
        let stats = InMemoryStatsProvider(championRoleStatsByRole: [.middle: [ahri: row]])
        #expect(stats.championRoleStats(in: .middle) == [ahri: row])
        #expect(stats.championRoleStats(in: .top).isEmpty)
    }

    @Test func servesLoadoutCandidatesOnlyForTheirChampionAndRole() {
        let page = RunePageCandidate(
            page: RunePage(
                primaryStyle: PerkStyleID(rawValue: 8100), subStyle: PerkStyleID(rawValue: 8200),
                perks: [8112, 8143, 8138, 8135, 8226, 8237, 5008, 5008, 5011].map(PerkID.init)),
            games: 484, wins: 222)
        let spells = SpellPairCandidate(
            spellA: SummonerSpellID(rawValue: 4), spellB: SummonerSpellID(rawValue: 14),
            games: 627, wins: 294)
        let build = ItemBuildCandidate(
            layer: .core, items: [3031, 3046, 3094].map(ItemID.init), games: 426, wins: 208)
        let skills = SkillOrderCandidate(
            order: SkillOrder(maxOrder: [.q, .w, .e], sequence: [.q, .w, .e, .q]),
            games: 336, wins: 154)
        let stats = InMemoryStatsProvider(
            runePagesByChampion: [ahri: [.middle: [page]]],
            spellPairsByChampion: [ahri: [.middle: [spells]]],
            itemBuildsByChampion: [ahri: [.middle: [build]]],
            skillOrdersByChampion: [ahri: [.middle: [skills]]])

        #expect(stats.runePages(for: ahri, role: .middle) == [page])
        #expect(stats.spellPairs(for: ahri, role: .middle) == [spells])
        #expect(stats.itemBuilds(for: ahri, role: .middle) == [build])
        #expect(stats.skillOrders(for: ahri, role: .middle) == [skills])
        #expect(stats.runePages(for: ahri, role: .top).isEmpty)
        #expect(stats.itemBuilds(for: ChampionID(rawValue: 238), role: .middle).isEmpty)
    }
}
