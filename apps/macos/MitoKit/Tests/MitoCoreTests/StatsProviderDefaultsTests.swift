import MitoCore
import Testing

struct StatsProviderDefaultsTests {
    private struct RoleGamesOnly: StatsProvider {
        func roleGames(for champion: ChampionID) -> [Role: Int] { [.middle: 900] }
    }

    private let ahri = ChampionID(rawValue: 103)
    private let zed = ChampionID(rawValue: 238)

    @Test func aProviderWithoutPhaseSixDataHasNoMeta() {
        #expect(RoleGamesOnly().meta == nil)
    }

    @Test func aProviderWithoutPhaseSixDataHasNoChampionRoleStats() {
        #expect(RoleGamesOnly().championRoleStats(in: .middle).isEmpty)
    }

    @Test func aProviderWithoutPhaseSixDataHasNoLoadoutCandidates() {
        let stats = RoleGamesOnly()
        #expect(stats.runePages(for: ahri, role: .middle).isEmpty)
        #expect(stats.spellPairs(for: ahri, role: .middle).isEmpty)
        #expect(stats.itemBuilds(for: ahri, role: .middle).isEmpty)
        #expect(stats.skillOrders(for: ahri, role: .middle).isEmpty)
    }

    @Test func aProviderWithoutPhaseSevenDataHasNoRelations() {
        let stats = RoleGamesOnly()
        #expect(stats.matchup(for: ahri, role: .middle, against: zed) == nil)
        #expect(stats.synergy(for: ahri, role: .middle, with: zed, allyRole: .jungle) == nil)
        #expect(stats.versusTeam(for: ahri, role: .middle, against: zed) == nil)
        #expect(stats.profileStats(for: ahri, role: .middle, against: .heavyAD) == nil)
    }

    @Test func aProviderWithoutPhaseSevenDataHasNoProfileBansOrFlags() {
        let stats = RoleGamesOnly()
        #expect(stats.championProfile(for: ahri, role: .middle) == nil)
        #expect(stats.bans(of: ahri) == nil)
        #expect(stats.flags(of: ahri).isEmpty)
    }

    @Test func aProviderWithoutPhaseSevenDataHasNoAdaptedLoadoutCandidates() {
        let stats = RoleGamesOnly()
        #expect(stats.runePages(for: ahri, role: .middle, against: zed).isEmpty)
        #expect(stats.spellPairs(for: ahri, role: .middle, against: zed).isEmpty)
        #expect(stats.itemBuilds(for: ahri, role: .middle, against: zed).isEmpty)
        #expect(stats.runePages(for: ahri, role: .middle, against: .heavyAP).isEmpty)
        #expect(stats.finalItems(for: ahri, role: .middle).isEmpty)
        #expect(stats.finalItems(for: ahri, role: .middle, against: .heavyAP).isEmpty)
    }

    @Test func aProviderWithoutDurationCurvesHasNoBuckets() {
        #expect(RoleGamesOnly().durationCurves(for: ahri, role: .middle).isEmpty)
    }

    @Test func aProviderWithoutItemClassesClassifiesNothingAsAntiheal() {
        let morello = ItemID(rawValue: 3165)
        #expect(RoleGamesOnly().itemClass(of: morello) == nil)
        #expect(!RoleGamesOnly().isAntiheal(morello))
    }
}
