public struct SkillOrder: Hashable, Sendable {
    public enum Ability: String, CaseIterable, Hashable, Sendable {
        case q = "Q"
        case w = "W"
        case e = "E"
        case r = "R"
    }

    /// Three abilities, or four when the kit levels R as a basic (`RQWE`).
    public let maxOrder: [Ability]
    /// Up to 18 levels.
    public let sequence: [Ability]

    public init(maxOrder: [Ability], sequence: [Ability]) {
        self.maxOrder = maxOrder
        self.sequence = sequence
    }
}
