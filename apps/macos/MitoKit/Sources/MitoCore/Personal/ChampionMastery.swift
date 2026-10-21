/// The user's mastery of one champion (§19.1). Read live from the client, never stored (§17).
public struct ChampionMastery: Hashable, Sendable {
    public let champion: ChampionID
    public let points: Int
    public let level: Int

    public init(champion: ChampionID, points: Int, level: Int) {
        self.champion = champion
        self.points = points
        self.level = level
    }
}
