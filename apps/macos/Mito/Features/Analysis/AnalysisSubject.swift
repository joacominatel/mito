import MitoAssets
import MitoCore
import MitoEngine
import MitoStore

/// What every analysis tab reads (§20.2): your champion and role, the lane opponent, both
/// teams, and the data to analyze them with. Champions and roles only, never a player (§5).
struct AnalysisSubject {
    struct Champion: Hashable {
        enum Source: Hashable {
            case locked
            case hovered
            /// The top pick recommendation, standing in until you lock or hover one.
            case recommended
        }

        let id: ChampionID
        let source: Source

        /// Not your pick yet: a tab says "si elegís Ahri…".
        var isRecommendation: Bool { source == .recommended }
    }

    /// Assigned roles are facts; inferred ones carry their probability and are never shown as
    /// fact (§12.3).
    enum SlotRole: Hashable {
        case assigned(Role)
        case inferred(Role, probability: Double)
        /// Inferred with no games behind it: a guess.
        case guessed(Role, probability: Double)

        var role: Role {
            switch self {
            case .assigned(let role), .inferred(let role, _), .guessed(let role, _): role
            }
        }

        /// 1 when the client assigned the role.
        var probability: Double {
            switch self {
            case .assigned: 1
            case .inferred(_, let probability), .guessed(_, let probability): probability
            }
        }
    }

    struct Slot: Hashable, Identifiable {
        /// The champ-select cell.
        let id: Int
        let champion: ChampionID?
        let hover: ChampionID?
        let role: SlotRole?
        let isMe: Bool
    }

    struct LaneOpponent: Hashable {
        let cellId: Int
        let champion: ChampionID
        let role: SlotRole

        var probability: Double { role.probability }
    }

    let queue: QueueType
    /// `nil` with nothing locked or hovered and no pick recommendation.
    let champion: Champion?
    /// The assigned role, or blind pick's chosen or default one (§20.3). `nil` in ARAM.
    let role: Role?
    /// The enemy inferred in `role`; `nil` when there is none.
    let laneOpponent: LaneOpponent?
    /// Includes you.
    let allies: [Slot]
    let enemies: [Slot]
    /// The open snapshot's; `meta` is `nil` without one.
    let stats: any StatsProvider
    /// The installed curated tips (§14.12); `.empty` without a tips file.
    let tips: CuratedTips
    /// Read once per champ select by `ChampSelectModel`.
    let personal: PersonalInputs
    let names: ReasonNames
    /// The client's game data; `nil` until it loads.
    let gameData: GameData?

    var meta: SnapshotMeta? { stats.meta }
}

extension AnalysisSubject {
    /// `topPick` runs only when you have neither locked nor hovered a champion.
    static func derive(
        draft: DraftContext, role: Role?, enemyRoles: [Int: InferredRole],
        topPick: () -> ChampionID?, stats: any StatsProvider, tips: CuratedTips = .empty,
        personal: PersonalInputs,
        names: ReasonNames, gameData: GameData? = nil
    ) -> AnalysisSubject {
        let allies = draft.allies.map { slot in
            Slot(
                id: slot.cellId, champion: slot.champion, hover: slot.hover,
                role: slot.role.map(SlotRole.assigned), isMe: slot.cellId == draft.myCellId)
        }
        let enemies = draft.enemies.map { slot in
            Slot(
                id: slot.cellId, champion: slot.champion, hover: slot.hover,
                role: slot.role.map(SlotRole.assigned) ?? enemyRoles[slot.cellId].flatMap(slotRole),
                isMe: false)
        }
        return AnalysisSubject(
            queue: draft.queue, champion: champion(in: allies, topPick: topPick), role: role,
            laneOpponent: role.flatMap { laneOpponent(in: enemies, role: $0) },
            allies: allies, enemies: enemies, stats: stats, tips: tips, personal: personal,
            names: names,
            gameData: gameData)
    }

    private static func champion(in allies: [Slot], topPick: () -> ChampionID?) -> Champion? {
        let me = allies.first(where: \.isMe)
        if let locked = me?.champion { return Champion(id: locked, source: .locked) }
        if let hover = me?.hover { return Champion(id: hover, source: .hovered) }
        return topPick().map { Champion(id: $0, source: .recommended) }
    }

    private static func slotRole(_ inferred: InferredRole) -> SlotRole? {
        guard let role = inferred.role else { return nil }
        return inferred.isUniformFallback
            ? .guessed(role, probability: inferred.roleConfidence)
            : .inferred(role, probability: inferred.roleConfidence)
    }

    /// An assigned enemy beats an inferred one; among inferred, the likeliest.
    private static func laneOpponent(in enemies: [Slot], role: Role) -> LaneOpponent? {
        let candidates = enemies.compactMap { slot -> LaneOpponent? in
            guard let champion = slot.champion, let slotRole = slot.role, slotRole.role == role
            else { return nil }
            return LaneOpponent(cellId: slot.id, champion: champion, role: slotRole)
        }
        return candidates.max { $0.probability < $1.probability }
    }
}
