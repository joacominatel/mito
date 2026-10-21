import MitoCore

@testable import MitoEngine

/// Thresholds that are exact in binary, so "at" and "just under" are exact comparisons.
let exactRules = ProfileRules(
    minimumChampions: 3, heavyADPhysicalShare: 0.625, heavyAPMagicShare: 0.5625,
    heavyCCScore: 0.5, mixedExcludes: [.heavyAD, .heavyAP])

func championProfile(
    physical: Double = 0.5, magic: Double = 0.5, damage: Double = 1, tankiness: Double = 0.8,
    cc: Double = 0.8
) -> ChampionProfile {
    ChampionProfile(
        physicalShare: physical, magicShare: magic, trueShare: 1 - physical - magic,
        damagePerMinute: damage, tankiness: tankiness, ccScore: cc, timelineGames: 0)
}

func team(
    members: Int = 4, physical: Double = 0.5, magic: Double = 0.5, ccScore: Double = 0
) -> TeamProfile {
    TeamProfile(
        profiledMembers: members, physicalShare: physical, magicShare: magic, tankiness: 0,
        ccScore: ccScore, topTankiness: 0, hasEngage: false)
}

func compositionMeta(rules: ProfileRules? = exactRules) -> SnapshotMeta {
    SnapshotMeta(
        patch: Patch(rawValue: "16.21"),
        queue: QueueID(rawValue: 420),
        bracket: .emeraldPlus,
        matches: 1_000_000,
        blendPatches: [Patch(rawValue: "16.21")],
        thresholds: [.championRole: SampleThreshold(minimum: 200, reliable: 1_000)],
        priors: SmoothingPriors(
            championRoleStrength: 100, championRoleBaseline: 0.5, relationStrength: 200,
            loadoutStrength: 500),
        tierCutoffs: [:],
        profileRules: rules)
}

func draft(myCellId: Int = 0, allies: [DraftSlot] = [], enemies: [DraftSlot] = [])
    -> DraftContext
{
    DraftContext(
        queue: .rankedSolo, patch: Patch(rawValue: "16.21"), myRole: .middle, myCellId: myCellId,
        allies: allies, enemies: enemies, bans: [], pickable: [], phase: .banPick,
        isMyTurnToPick: true, isMyTurnToBan: false)
}

func slot(_ cellId: Int, _ champion: ChampionID?, _ role: Role?) -> DraftSlot {
    DraftSlot(
        cellId: cellId, champion: champion, hover: nil, role: role,
        roleConfidence: role == nil ? 0 : 1)
}

/// 1,000 games at 0.5: the early buckets at 0.6, the middle at 0.5, and the late at 0.4.
let earlyCurve: [DurationBucket: RelationStats] = [
    .under20: RelationStats(games: 150, wins: 90),
    .from20To25: RelationStats(games: 150, wins: 90),
    .from25To30: RelationStats(games: 200, wins: 100),
    .from30To35: RelationStats(games: 200, wins: 100),
    .from35To40: RelationStats(games: 150, wins: 60),
    .over40: RelationStats(games: 150, wins: 60),
]

/// `earlyCurve` mirrored: early −0.06, late +0.06.
let lateCurve: [DurationBucket: RelationStats] = [
    .under20: RelationStats(games: 150, wins: 60),
    .from20To25: RelationStats(games: 150, wins: 60),
    .from25To30: RelationStats(games: 200, wins: 100),
    .from30To35: RelationStats(games: 200, wins: 100),
    .from35To40: RelationStats(games: 150, wins: 90),
    .over40: RelationStats(games: 150, wins: 90),
]

/// Every bucket at 0.5: no strength either way.
let flatCurve: [DurationBucket: RelationStats] = Dictionary(
    uniqueKeysWithValues: DurationBucket.allCases.map { ($0, RelationStats(games: 100, wins: 50)) })
