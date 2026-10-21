/// One explained fact behind a recommendation or a loadout part (§13.5, §18). It carries the
/// numbers, never copy: the UI renders it (`ReasonRow`, §22.3). Deltas and shares are fractions
/// (`0.021` is +2,1 points); signs carry direction.
public struct Reason: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// §18.3 `matchup`: `delta` is `matchup_delta` against the lane opponent over `games`.
        case matchup(opponent: ChampionID, delta: Double, games: Int)
        /// §18.3 matchup backoff: no usable `matchup_stats` row against `opponent`, so `delta`
        /// is the `games`-weighted `matchup_delta` against the active enemy `profiles` with a
        /// usable `champ_vs_profile` row, and `games` their sum. The sample is the lowest
        /// among those rows.
        case profileMatchup(
            opponent: ChampionID, profiles: [EnemyProfile], delta: Double, games: Int)
        /// §18.3 `vs_team`: the delta against a locked enemy outside the lane.
        case versusEnemy(enemy: ChampionID, delta: Double, games: Int)
        /// §18.3 `synergy`: the delta with a locked ally in its role.
        case synergy(ally: ChampionID, allyRole: Role, delta: Double, games: Int)
        /// §18.3 `meta`: the tier of `wr_smoothed(champ, role)` and its `games`.
        case meta(tier: Tier, games: Int)
        /// §18.3, §19.3 personal comfort ("Tu 3er campeón (41 partidas, 56 %)"): the user's
        /// own `games` with the champion in this role and their raw `winrate` over them.
        /// `poolRank` is the 1-based place in the role's pool order (§18.3), `nil` outside it.
        case comfort(poolRank: Int?, games: Int, winrate: Double)
        /// §18.4 damage balance: the allied `team_phys` or `team_magic` share that `adds` offsets.
        case fillsDamageGap(adds: DamageType, alliedShare: Double)
        /// §18.4 frontline: the candidate's `tankiness` when the team has no frontline.
        case addsFrontline(tankiness: Double)
        /// §18.4 CC: the candidate's `cc_score` when the team's CC is low.
        case addsCrowdControl(ccScore: Double)
        /// §18.4 engage: the candidate has the `engage` flag and no ally does.
        case addsEngage
        /// §18.4 power curve: `early_strength` of the candidate and of the allied team.
        case powerCurve(early: Double, teamEarly: Double)
        /// §18.5 `amenaza`: `delta` is `matchup_delta(pick, your role, banned)`, so a threat is
        /// negative ("−4,2 % para tu Ahri").
        case threatens(pick: ChampionID, delta: Double, games: Int)
        /// §18.6–§18.9 general choice: its usage in the context and its smoothed winrate.
        case generalChoice(part: LoadoutPart, usage: Double, winrate: Double, games: Int)
        /// §18.6–§18.8: the part follows the rows against the lane opponent.
        case adaptedToOpponent(part: LoadoutPart, opponent: ChampionID, games: Int)
        /// §18.6–§18.7: the part follows the rows against an active enemy profile.
        case adaptedToProfile(part: LoadoutPart, profile: EnemyProfile, games: Int)
        /// §18.7 flag rules: `enemies` locked enemies carry `flag` (antiheal, Banshee, Tabis).
        case countersFlag(item: ItemID, flag: ChampionFlag, enemies: Int)
        /// §18.7 situational: `buy_rate` and winrate against `profile` versus the `'any'` baseline.
        case situationalItem(
            item: ItemID, profile: EnemyProfile, buyRate: Double, baselineBuyRate: Double,
            winrateDelta: Double)
    }

    public let kind: Kind
    /// The level of the sample behind the numbers (§18.2); `nil` when the reason is not a
    /// count, like a flag rule.
    public let sample: SampleLevel?

    public init(kind: Kind, sample: SampleLevel?) {
        self.kind = kind
        self.sample = sample
    }
}

/// The damage types the §18.4 balance rule weighs; true damage is never a gap.
public enum DamageType: Hashable, Sendable {
    case physical
    case magic
}

/// The loadout part a reason explains (§13, §18.6–§18.9).
public enum LoadoutPart: Hashable, Sendable {
    case runes
    case spells
    /// One block of the item set.
    case items(BuildLayer)
    case skillOrder
}
