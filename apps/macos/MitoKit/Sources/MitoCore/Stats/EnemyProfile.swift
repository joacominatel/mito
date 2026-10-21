/// An enemy team profile (§18.4). Multi-label: a team can be `heavyAD` and `heavyCC` at once.
/// Raw values are the `enemy_profile` encoding of `champ_vs_profile` and its siblings (§17).
public enum EnemyProfile: RawRepresentable, Hashable, Sendable {
    case heavyAD
    case heavyAP
    /// Neither `heavyAD` nor `heavyAP`.
    case mixed
    case heavyCC
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "heavy_ad": self = .heavyAD
        case "heavy_ap": self = .heavyAP
        case "mixed": self = .mixed
        case "heavy_cc": self = .heavyCC
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .heavyAD: "heavy_ad"
        case .heavyAP: "heavy_ap"
        case .mixed: "mixed"
        case .heavyCC: "heavy_cc"
        case .unknown(let value): value
        }
    }
}

/// `meta.profile_rules` (§17, §18.4): the calibrated thresholds the pipeline classified every
/// match with, so champ select is classified with the same numbers.
public struct ProfileRules: Hashable, Sendable {
    /// `min_champions`: fewest locked members with a profile before a team is classified.
    public let minimumChampions: Int
    /// `heavy_ad.phys_share_weighted`: inclusive minimum `team_phys` for `heavyAD`.
    public let heavyADPhysicalShare: Double
    /// `heavy_ap.magic_share_weighted`: inclusive minimum `team_magic` for `heavyAP`.
    public let heavyAPMagicShare: Double
    /// `heavy_cc.cc_score_mean`: inclusive minimum mean `cc_score` for `heavyCC`.
    public let heavyCCScore: Double
    /// `mixed.not`: a team is `mixed` when it has none of these (`heavyAD` and `heavyAP`).
    public let mixedExcludes: Set<EnemyProfile>

    public init(
        minimumChampions: Int,
        heavyADPhysicalShare: Double,
        heavyAPMagicShare: Double,
        heavyCCScore: Double,
        mixedExcludes: Set<EnemyProfile>
    ) {
        self.minimumChampions = minimumChampions
        self.heavyADPhysicalShare = heavyADPhysicalShare
        self.heavyAPMagicShare = heavyAPMagicShare
        self.heavyCCScore = heavyCCScore
        self.mixedExcludes = mixedExcludes
    }
}
