import MitoCore
import Testing

struct StatsProviderDefaultsTests {
    private struct RoleGamesOnly: StatsProvider {
        func roleGames(for champion: ChampionID) -> [Role: Int] { [.middle: 900] }
    }

    private let ahri = ChampionID(rawValue: 103)

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
}
