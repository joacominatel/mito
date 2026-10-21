/// Raw values are the `meta.tier_cutoffs` keys (§17).
public enum Tier: String, CaseIterable, Hashable, Sendable {
    case s = "S"
    case a = "A"
    case b = "B"
    case c = "C"
    case d = "D"
}
