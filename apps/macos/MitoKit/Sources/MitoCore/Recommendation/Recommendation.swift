/// A ranked champion with its score explained (§18.3, §18.5).
public struct Recommendation<Component: Hashable & Sendable>: Hashable, Sendable, Identifiable {
    public var id: ChampionID { champion }

    public let champion: ChampionID
    /// The weighted sum, in winrate points as fractions (§18.3).
    public let score: Double
    /// Each weighted term (picks) or factor (bans) of `score`; one that does not apply is absent.
    public let components: [Component: Double]
    /// Ordered by impact, strongest first (§18.3).
    public let reasons: [Reason]
    /// The `champ_role` sample level of the candidate (§18.2, "confidence" in §18.3).
    public let confidence: SampleLevel

    public init(
        champion: ChampionID, score: Double, components: [Component: Double], reasons: [Reason],
        confidence: SampleLevel
    ) {
        self.champion = champion
        self.score = score
        self.components = components
        self.reasons = reasons
        self.confidence = confidence
    }
}

public typealias PickRecommendation = Recommendation<PickComponent>
public typealias BanRecommendation = Recommendation<BanComponent>

/// The terms of `score(c)` (§18.3).
public enum PickComponent: CaseIterable, Hashable, Sendable {
    /// `w_meta · meta(c, r)`.
    case meta
    /// `w_matchup · matchup(c, r, lane opponent)`.
    case matchup
    /// `w_counter · Σ vs_team(c, r, e)`.
    case counter
    /// `w_synergy · Σ synergy(c, r, a, role_a)`.
    case synergy
    /// `w_comp · comp_fit`.
    case composition
    /// `w_personal · personal(c, r)` (§19).
    case personal
    /// `− penalties(c)`, stored negative.
    case penalties
}

/// The factors of `ban_score(e) = presencia(e) · amenaza(e)` (§18.5).
public enum BanComponent: CaseIterable, Hashable, Sendable {
    /// `presencia(e)`.
    case presence
    /// `amenaza(e)`.
    case threat
}
