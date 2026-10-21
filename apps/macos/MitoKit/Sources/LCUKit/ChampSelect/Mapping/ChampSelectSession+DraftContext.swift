public import MitoCore

extension ChampSelectSession {
    /// `nil` when the local player or the phase cannot be placed (`MITO_CONTEXT.md` §12.2).
    public func draftContext(
        queue: QueueType,
        patch: Patch,
        pickable: Set<ChampionID>
    ) -> DraftContext? {
        guard let myCellId = localPlayerCellId,
            let me = myTeam.first(where: { $0.cellId == myCellId }),
            let phase = timer?.phase.flatMap(DraftPhase.init)
        else { return nil }

        let steps = Array(actions.joined())
        let bannedByActions = steps.filter { $0.type == .ban && $0.completed == true }
            .compactMap(\.championId)

        func isMyTurn(_ kind: Action.Kind) -> Bool {
            steps.contains {
                $0.type == kind && $0.isInProgress == true && $0.completed != true
                    && $0.actorCellId == myCellId
            }
        }

        return DraftContext(
            queue: queue,
            patch: patch,
            myRole: me.assignedPosition.role,
            myCellId: myCellId,
            allies: myTeam.compactMap { DraftSlot($0, steps: steps) },
            enemies: theirTeam.compactMap { DraftSlot($0, steps: steps) },
            bans: Set(bans.myTeamBans + bans.theirTeamBans + bannedByActions),
            pickable: pickable,
            phase: phase,
            isMyTurnToPick: isMyTurn(.pick),
            isMyTurnToBan: isMyTurn(.ban)
        )
    }
}

extension DraftPhase {
    fileprivate init?(_ phase: ChampSelectSession.Timer.Phase) {
        switch phase {
        case .planning: self = .planning
        case .banPick: self = .banPick
        case .finalization: self = .finalization
        case .unknown: return nil
        }
    }
}

extension DraftSlot {
    // A member without a cell cannot be placed in the draft.
    fileprivate init?(_ member: ChampSelectSession.Member, steps: [ChampSelectSession.Action]) {
        guard let cellId = member.cellId else { return nil }
        let picks = steps.filter { $0.type == .pick && $0.actorCellId == cellId }
        // During the player's own turn `championId` is the grid hover, so only a completed pick locks.
        let locked: ChampionID? =
            if picks.isEmpty {
                member.championId
            } else if let pick = picks.first(where: { $0.completed == true }) {
                pick.championId ?? member.championId
            } else {
                nil
            }
        let role = member.assignedPosition.role
        self.init(
            cellId: cellId,
            champion: locked,
            hover: (locked == nil ? member.championId : nil) ?? member.championPickIntent,
            role: role,
            roleConfidence: role == nil ? 0 : 1
        )
    }
}
