public import MitoCore

public enum TeamSide: Hashable, Sendable {
    case allies
    case enemies
}

/// A textual "condición de victoria" of the Composición tab (§20.2), with what it rests on.
public enum WinCondition: Hashable, Sendable {
    /// The side is early and the other is not.
    case closeEarly(TeamSide, byMinute: Int)
    /// The side is late and the other is not.
    case scaleLate(TeamSide, fromMinute: Int)
    /// The side's frontline is a level above the other's.
    case frontline(TeamSide)
    /// The side's CC is a level above the other's.
    case crowdControl(TeamSide)
    /// The enemy deals more than `CompFit.damageGapShare` of one damage type.
    case oneSidedEnemyDamage(DamageType, share: Double)
}

extension Composition {
    /// In this order: curves, frontline, CC, enemy damage. Each comparison needs both teams with
    /// `CompFit.minimumAllies` profiled members; the curves, as many members with a curve.
    static func winConditions(allies: TeamRead, enemies: TeamRead) -> [WinCondition] {
        let minimum = CompFit.minimumAllies
        let comparable =
            allies.profile.profiledMembers >= minimum && enemies.profile.profiledMembers >= minimum
        let sides: [(TeamSide, TeamRead, TeamRead)] = [
            (.allies, allies, enemies), (.enemies, enemies, allies),
        ]
        var conditions: [WinCondition] = []

        for (side, team, other) in sides {
            guard let phase = team.curve?.phase, let otherPhase = other.curve?.phase else {
                continue
            }
            if phase == .early, otherPhase != .early {
                conditions.append(.closeEarly(side, byMinute: PowerCurve.earlyEndMinutes))
            }
            if phase == .late, otherPhase != .late {
                conditions.append(.scaleLate(side, fromMinute: PowerCurve.lateStartMinutes))
            }
        }
        if comparable {
            for (side, team, other) in sides {
                if let level = team.frontline, let otherLevel = other.frontline, level > otherLevel
                {
                    conditions.append(.frontline(side))
                }
            }
            for (side, team, other) in sides {
                if let level = team.crowdControl, let otherLevel = other.crowdControl,
                    level > otherLevel
                {
                    conditions.append(.crowdControl(side))
                }
            }
        }
        if enemies.profile.profiledMembers >= minimum {
            if enemies.profile.physicalShare > CompFit.damageGapShare {
                conditions.append(
                    .oneSidedEnemyDamage(.physical, share: enemies.profile.physicalShare))
            } else if enemies.profile.magicShare > CompFit.damageGapShare {
                conditions.append(.oneSidedEnemyDamage(.magic, share: enemies.profile.magicShare))
            }
        }
        return conditions
    }
}
