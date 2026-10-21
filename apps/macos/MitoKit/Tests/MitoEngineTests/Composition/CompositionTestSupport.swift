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
