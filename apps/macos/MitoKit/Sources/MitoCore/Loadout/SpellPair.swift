/// Lower ID first from the engine; `SpellImporter` sets the client slots by the Flash rule.
public struct SpellPair: Hashable, Sendable {
    public let first: SummonerSpellID
    public let second: SummonerSpellID

    public init(first: SummonerSpellID, second: SummonerSpellID) {
        self.first = first
        self.second = second
    }
}
