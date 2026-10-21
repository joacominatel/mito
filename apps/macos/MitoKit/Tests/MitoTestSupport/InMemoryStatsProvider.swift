public import MitoCore

public struct InMemoryStatsProvider: StatsProvider {
    public var roleGamesByChampion: [ChampionID: [Role: Int]]

    public init(roleGamesByChampion: [ChampionID: [Role: Int]] = [:]) {
        self.roleGamesByChampion = roleGamesByChampion
    }

    public func roleGames(for champion: ChampionID) -> [Role: Int] {
        roleGamesByChampion[champion] ?? [:]
    }
}
