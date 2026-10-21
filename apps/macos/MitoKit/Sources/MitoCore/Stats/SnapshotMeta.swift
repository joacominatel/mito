/// The `meta` table of the open snapshot (`MITO_CONTEXT.md` §17): its identity and the
/// parameters the app computes rates with, the same ones the exporter filtered with.
public struct SnapshotMeta: Hashable, Sendable {
    public let patch: Patch
    public let queue: QueueID
    public let bracket: Bracket
    /// Matches in the file after the cold-start blend; the denominator of pick and ban rates.
    public let matches: Int
    /// Patches blended into the file, current first (`["16.21", "16.20"]`).
    public let blendPatches: [Patch]
    /// Sample thresholds by data kind; a kind missing from the file is missing here.
    public let thresholds: [SampleKind: SampleThreshold]
    public let priors: SmoothingPriors
    /// Minimum `wr_smoothed(champ, role)` per tier; below C is D, so D has no entry.
    public let tierCutoffs: [Tier: Double]
    /// `profile_rules` (§18.4); `nil` when the file carries none, so no team gets a profile.
    public let profileRules: ProfileRules?

    public init(
        patch: Patch,
        queue: QueueID,
        bracket: Bracket,
        matches: Int,
        blendPatches: [Patch],
        thresholds: [SampleKind: SampleThreshold],
        priors: SmoothingPriors,
        tierCutoffs: [Tier: Double],
        profileRules: ProfileRules? = nil
    ) {
        self.patch = patch
        self.queue = queue
        self.bracket = bracket
        self.matches = matches
        self.blendPatches = blendPatches
        self.thresholds = thresholds
        self.priors = priors
        self.tierCutoffs = tierCutoffs
        self.profileRules = profileRules
    }
}

/// Raw values are the `meta.thresholds` keys (§18.2).
public enum SampleKind: String, CaseIterable, Hashable, Sendable {
    case championRole = "champ_role"
    case matchup
    case synergy
    case vsTeam = "vs_team"
    case profile
    case runePage = "rune_page"
    case buildLayer = "build_layer"
    case itemVsProfile = "item_vs_profile"
    case spells
    case skillOrder = "skill_order"
}

public struct SampleThreshold: Hashable, Sendable {
    /// Fewest games for a row to be used at all.
    public let minimum: Int
    /// Fewest games for a row to be shown as reliable rather than low sample.
    public let reliable: Int

    public init(minimum: Int, reliable: Int) {
        self.minimum = minimum
        self.reliable = reliable
    }
}

/// `meta.priors` (§18.1): strengths `m` are in games.
public struct SmoothingPriors: Hashable, Sendable {
    public let championRoleStrength: Double
    /// `p0` for (champ, role); every other context centers on `wr_smoothed(champ, role)`.
    public let championRoleBaseline: Double
    /// Matchup, synergy, vs_team and enemy profile.
    public let relationStrength: Double
    /// Runes, items, spells and skill orders.
    public let loadoutStrength: Double

    public init(
        championRoleStrength: Double,
        championRoleBaseline: Double,
        relationStrength: Double,
        loadoutStrength: Double
    ) {
        self.championRoleStrength = championRoleStrength
        self.championRoleBaseline = championRoleBaseline
        self.relationStrength = relationStrength
        self.loadoutStrength = loadoutStrength
    }
}
