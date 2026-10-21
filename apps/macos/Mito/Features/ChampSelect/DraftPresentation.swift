import Foundation
import MitoAssets
import MitoCore
import MitoEngine

/// One cell of a team column, ready to render. Never carries a player's identity (§5).
struct DraftSlotRow: Identifiable, Hashable {
    enum Pick: Hashable {
        case locked(String)
        case hovering(String)
        case empty
    }

    enum RoleLabel: Hashable {
        case assigned(Role)
        /// Inferred from data; `confidence` is the marginal probability (§12.3).
        case inferred(Role, confidence: Double)
        /// Inferred with no data behind it: a guess, shown as such.
        case uncertain(Role)
        case none
    }

    let id: Int
    let pick: Pick
    let role: RoleLabel
    let turn: ChampSelectModel.Turn?
    let isMe: Bool
    /// The locked or hovered champion.
    var champion: ChampionID?

    var iconState: ChampionIcon.State {
        switch pick {
        case .locked: .locked
        case .hovering: .hover
        case .empty: .normal
        }
    }

    var accessibilityLabel: String {
        var parts: [String] = []
        if isMe { parts.append(String(localized: "Vos", table: "ChampSelect")) }
        switch role {
        case .assigned(let role): parts.append(String(localized: role.name))
        case .inferred(let role, let confidence):
            let percent = confidence.formatted(.percent.precision(.fractionLength(0)))
            parts.append(
                String(
                    localized: "Rol probable: \(String(localized: role.name)), \(percent)",
                    table: "ChampSelect"))
        case .uncertain(let role):
            parts.append(
                String(
                    localized: "Rol incierto, quizás \(String(localized: role.name))",
                    table: "ChampSelect"))
        case .none: break
        }
        switch pick {
        case .locked(let name):
            parts.append(String(localized: "\(name), lockeado", table: "ChampSelect"))
        case .hovering(let name):
            parts.append(String(localized: "\(name), en hover", table: "ChampSelect"))
        case .empty:
            parts.append(String(localized: "Sin campeón", table: "ChampSelect"))
        }
        switch turn {
        case .pick: parts.append(String(localized: "Eligiendo", table: "ChampSelect"))
        case .ban: parts.append(String(localized: "Baneando", table: "ChampSelect"))
        case nil: break
        }
        return parts.joined(separator: ", ")
    }
}

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

extension Role {
    /// The column abbreviation of §20.1.
    var shortLabel: LocalizedStringResource {
        switch self {
        case .top: LocalizedStringResource("TOP", table: "ChampSelect")
        case .jungle: LocalizedStringResource("JG", table: "ChampSelect")
        case .middle: LocalizedStringResource("MID", table: "ChampSelect")
        case .bottom: LocalizedStringResource("ADC", table: "ChampSelect")
        case .utility: LocalizedStringResource("SUP", table: "ChampSelect")
        }
    }

    var name: LocalizedStringResource {
        switch self {
        case .top: LocalizedStringResource("Top", table: "ChampSelect")
        case .jungle: LocalizedStringResource("Jungla", table: "ChampSelect")
        case .middle: LocalizedStringResource("Mid", table: "ChampSelect")
        case .bottom: LocalizedStringResource("Tirador", table: "ChampSelect")
        case .utility: LocalizedStringResource("Soporte", table: "ChampSelect")
        }
    }
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
