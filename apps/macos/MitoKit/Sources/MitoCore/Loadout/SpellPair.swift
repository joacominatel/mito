/// Slot order as sent to the client (`spell1Id`, `spell2Id`), after the Flash position rule.
public struct SpellPair: Hashable, Sendable {
    public let first: SummonerSpellID
    public let second: SummonerSpellID

    public init(first: SummonerSpellID, second: SummonerSpellID) {
        self.first = first
        self.second = second
    }
}
