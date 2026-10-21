import MitoCore
import MitoEngine

/// What the Composición tab shows (§20.2): both teams counted as `MitoEngine` counts them, plus
/// what the read assumes.
struct CompositionSummary {
    struct Team: Hashable {
        struct Member: Hashable {
            let champion: ChampionID
            let name: String
        }

        let read: TeamRead
        /// Every slot, locked or not: the "de 5" of "2 de 5 con datos".
        let size: Int
        /// The champions counted, in cell order, with or without a profile.
        let members: [Member]

        var profiled: Int { read.profile.profiledMembers }
        var isPartial: Bool { profiled < size }
        var hasData: Bool { profiled > 0 }
    }

    /// Your champion when it is not locked: the read includes it as if it were.
    enum AssumedPick: Hashable {
        case hovered(String)
        case recommended(String)
    }

    let allies: Team
    let enemies: Team
    /// By raw value, so the labels never shuffle.
    let enemyProfile: [EnemyProfile]
    let winConditions: [WinCondition]
    let assumedPick: AssumedPick?
    /// A locked enemy counts in an inferred role, never shown as fact (§12.3).
    let hasInferredEnemyRoles: Bool
    /// Curves and spikes measure Summoner's Rift games: ARAM leaves them out.
    let showsTiming: Bool
    /// Nobody counts yet: no locked champion and no pick of yours.
    let hasNoMembers: Bool

    var hasData: Bool { allies.hasData || enemies.hasData }

    init(subject: AnalysisSubject) {
        let me = subject.champion
        let allySlots = subject.allies.map { slot in
            DraftSlot(
                cellId: slot.id, champion: slot.isMe ? me?.id : slot.champion, hover: nil,
                role: slot.isMe
                    ? (Self.assigned(slot.role) ?? subject.role) : Self.assigned(slot.role),
                roleConfidence: 1)
        }
        // Inferred roles are left for `Composition.members` to infer again, as the engine does.
        let enemySlots = subject.enemies.map { slot in
            DraftSlot(
                cellId: slot.id, champion: slot.champion, hover: nil,
                role: Self.assigned(slot.role),
                roleConfidence: 1)
        }
        let allyMembers = Composition.members(of: allySlots, stats: subject.stats)
        let enemyMembers = Composition.members(of: enemySlots, stats: subject.stats)
        let read = Composition.read(
            allies: allyMembers, enemies: enemyMembers, stats: subject.stats,
            timing: subject.queue != .aram)

        func members(_ slots: [DraftSlot]) -> [Team.Member] {
            slots.compactMap(\.champion).map {
                Team.Member(champion: $0, name: subject.names.champion($0))
            }
        }
        allies = Team(read: read.allies, size: subject.allies.count, members: members(allySlots))
        enemies = Team(
            read: read.enemies, size: subject.enemies.count, members: members(enemySlots))
        enemyProfile = read.enemyProfile.sorted { $0.rawValue < $1.rawValue }
        winConditions = read.winConditions
        assumedPick = me.flatMap { champion in
            switch champion.source {
            case .locked: nil
            case .hovered: .hovered(subject.names.champion(champion.id))
            case .recommended: .recommended(subject.names.champion(champion.id))
            }
        }
        hasInferredEnemyRoles = subject.enemies.contains { slot in
            slot.champion != nil && slot.role != nil && Self.assigned(slot.role) == nil
        }
        showsTiming = subject.queue != .aram
        hasNoMembers = allyMembers.isEmpty && enemyMembers.isEmpty
    }

    private static func assigned(_ role: AnalysisSubject.SlotRole?) -> Role? {
        if case .assigned(let role) = role { return role }
        return nil
    }
}
