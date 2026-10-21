/// A `champion_profiles` row (§14.11, §17): what the comp fit of §18.4 weighs.
public struct ChampionProfile: Hashable, Sendable {
    /// `phys_share`: share of damage to champions that is physical.
    public let physicalShare: Double
    /// `magic_share`.
    public let magicShare: Double
    /// `true_share`.
    public let trueShare: Double
    /// `dmg_per_min`: the weight of this champion in its team's damage profile (§18.4).
    public let damagePerMinute: Double
    /// `tankiness`: 0–1 percentile within the role; the frontline rule reads it (§18.4).
    public let tankiness: Double
    /// `cc_score`: 0–1 percentile within the role; `heavy_cc` and the CC rule read it (§18.4).
    public let ccScore: Double
    /// `tl_games`: the timeline denominator of the fields below.
    public let timelineGames: Int
    /// `gold_diff_15`: mean against the lane opponent.
    public let goldDiffAt15: Double?
    /// `lvl6_s`: median second of the first R level.
    public let levelSixSeconds: Int?
    /// `item1_s`: median second of the first legendary.
    public let firstItemSeconds: Int?
    /// `item2_s`.
    public let secondItemSeconds: Int?
    /// `item3_s`; `nil` without a timeline sample.
    public let thirdItemSeconds: Int?

    public init(
        physicalShare: Double,
        magicShare: Double,
        trueShare: Double,
        damagePerMinute: Double,
        tankiness: Double,
        ccScore: Double,
        timelineGames: Int,
        goldDiffAt15: Double? = nil,
        levelSixSeconds: Int? = nil,
        firstItemSeconds: Int? = nil,
        secondItemSeconds: Int? = nil,
        thirdItemSeconds: Int? = nil
    ) {
        self.physicalShare = physicalShare
        self.magicShare = magicShare
        self.trueShare = trueShare
        self.damagePerMinute = damagePerMinute
        self.tankiness = tankiness
        self.ccScore = ccScore
        self.timelineGames = timelineGames
        self.goldDiffAt15 = goldDiffAt15
        self.levelSixSeconds = levelSixSeconds
        self.firstItemSeconds = firstItemSeconds
        self.secondItemSeconds = secondItemSeconds
        self.thirdItemSeconds = thirdItemSeconds
    }
}

/// Raw values are the `champion_flags.flag` encoding, curated per patch (§14.11, §17).
public enum ChampionFlag: RawRepresentable, Hashable, Sendable {
    /// Antiheal rule of §18.7.
    case highHeal
    /// Banshee rule of §18.7.
    case pointClickCC
    /// Tabis rule of §18.7.
    case autoAttacker
    case poke
    /// CC / engage rule of §18.4.
    case engage
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "high_heal": self = .highHeal
        case "point_click_cc": self = .pointClickCC
        case "auto_attacker": self = .autoAttacker
        case "poke": self = .poke
        case "engage": self = .engage
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .highHeal: "high_heal"
        case .pointClickCC: "point_click_cc"
        case .autoAttacker: "auto_attacker"
        case .poke: "poke"
        case .engage: "engage"
        case .unknown(let value): value
        }
    }
}
