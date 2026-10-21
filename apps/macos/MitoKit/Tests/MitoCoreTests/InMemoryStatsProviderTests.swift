import MitoCore
import MitoTestSupport
import Testing

struct InMemoryStatsProviderTests {
    @Test func servesTheGivenRoleGames() {
        let ahri = ChampionID(rawValue: 103)
        let stats = InMemoryStatsProvider(roleGamesByChampion: [ahri: [.middle: 900, .top: 12]])
        #expect(stats.roleGames(for: ahri) == [.middle: 900, .top: 12])
    }

    @Test func aChampionWithoutRowsHasNoRoleGames() {
        #expect(InMemoryStatsProvider().roleGames(for: ChampionID(rawValue: 950)).isEmpty)
    }
}
