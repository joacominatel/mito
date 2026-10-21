import MitoCore
import Testing

struct ChampionMasteryTests {
    // §5 and §25: the client's payload carries the PUUID; the value must not.
    @Test func holdsOnlyChampionPointsAndLevel() {
        let mastery = ChampionMastery(
            champion: ChampionID(rawValue: 103), points: 245_310, level: 14)
        #expect(
            Mirror(reflecting: mastery).children.compactMap(\.label)
                == ["champion", "points", "level"])
    }
}
