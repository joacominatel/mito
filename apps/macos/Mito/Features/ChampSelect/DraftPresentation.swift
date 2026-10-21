import Foundation
import MitoAssets
import MitoCore
import MitoEngine

extension ChampSelectModel {
    var allyRows: [DraftSlotRow] {
        guard let draft else { return [] }
        return draft.allies.map { row(for: $0, isMe: $0.cellId == draft.myCellId, roles: [:]) }
    }

    var enemyRows: [DraftSlotRow] {
        let roles = enemyRoles
        return draft?.enemies.map { row(for: $0, isMe: false, roles: roles) } ?? []
    }

    /// By name.
    var bans: [BannedChampion] {
        (draft?.bans ?? []).map { BannedChampion(id: $0, name: championName($0)) }
            .sorted { $0.name < $1.name }
    }

    /// The menu bar line (§22.4); `nil` outside champ select.
    var menuSummary: LocalizedStringResource? {
        guard let draft else { return nil }
        if draft.isMyTurnToPick {
            return LocalizedStringResource(
                "Champ select · tu turno de elegir", table: "ChampSelect")
        }
        if draft.isMyTurnToBan {
            return LocalizedStringResource(
                "Champ select · tu turno de banear", table: "ChampSelect")
        }
        let slots = draft.allies + draft.enemies
        let locked = slots.filter { $0.champion != nil }.count
        return LocalizedStringResource(
            "Champ select · \(locked) de \(slots.count) lockeados", table: "ChampSelect")
    }

    /// The champion of `menuRecommendation`.
    var menuRecommendedChampion: ChampionID? {
        switch recommendations {
        case .picks(let picks): picks.first?.champion
        case .bans(let bans): bans.first?.champion
        case .unavailable, nil: nil
        }
    }

    /// "Recomendado: Ahri (+3,8)" under the summary (§22.4); a ban during the ban phase.
    var menuRecommendation: LocalizedStringResource? {
        switch recommendations {
        case .picks(let picks):
            guard let top = picks.first else { return nil }
            return LocalizedStringResource(
                "Recomendado: \(championName(top.champion)) (\(WinratePoints.text(top.score)))",
                table: "ChampSelect")
        case .bans(let bans):
            guard let top = bans.first else { return nil }
            return LocalizedStringResource(
                "Ban recomendado: \(championName(top.champion))", table: "ChampSelect")
        case .unavailable, nil:
            return nil
        }
    }

    var reasonNames: ReasonNames {
        ReasonNames(
            champion: championName,
            item: { [gameData] id in
                if let name = gameData?.item(id)?.name, !name.isEmpty { return name }
                return String(localized: "Ítem \(String(id.rawValue))", table: "ChampSelect")
            })
    }

    func championName(_ id: ChampionID) -> String {
        if let name = gameData?.champion(id)?.name, !name.isEmpty { return name }
        return String(localized: "Campeón \(String(id.rawValue))", table: "ChampSelect")
    }

    private func row(for slot: DraftSlot, isMe: Bool, roles: [Int: InferredRole])
        -> DraftSlotRow
    {
        let pick: DraftSlotRow.Pick =
            if let champion = slot.champion {
                .locked(championName(champion))
            } else if let hover = slot.hover {
                .hovering(championName(hover))
            } else {
                .empty
            }
        let role: DraftSlotRow.RoleLabel =
            if let assigned = slot.role {
                .assigned(assigned)
            } else if let inferred = roles[slot.cellId], let guess = inferred.role {
                inferred.isUniformFallback
                    ? .uncertain(guess) : .inferred(guess, confidence: inferred.roleConfidence)
            } else {
                .none
            }
        return DraftSlotRow(
            id: slot.cellId, pick: pick, role: role, turn: turns[slot.cellId], isMe: isMe,
            champion: slot.champion ?? slot.hover)
    }
}

struct BannedChampion: Hashable {
    let id: ChampionID
    let name: String
}

extension QueueType {
    var label: LocalizedStringResource {
        switch self {
        case .rankedSolo: LocalizedStringResource("Ranked Solo/Duo", table: "ChampSelect")
        case .rankedFlex: LocalizedStringResource("Ranked Flex", table: "ChampSelect")
        case .normalDraft: LocalizedStringResource("Normal (draft)", table: "ChampSelect")
        case .normalBlind: LocalizedStringResource("Normal (blind)", table: "ChampSelect")
        case .aram: LocalizedStringResource("ARAM", table: "ChampSelect")
        case .other: LocalizedStringResource("Otra cola", table: "ChampSelect")
        }
    }
}

extension DraftPhase {
    var label: LocalizedStringResource {
        switch self {
        case .planning: LocalizedStringResource("Planificación", table: "ChampSelect")
        case .banPick: LocalizedStringResource("Bans y picks", table: "ChampSelect")
        case .finalization: LocalizedStringResource("Finalización", table: "ChampSelect")
        }
    }
}
