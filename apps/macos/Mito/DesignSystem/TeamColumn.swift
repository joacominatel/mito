import Foundation
import MitoCore
import MitoEngine
import SwiftUI

/// Whose ban or pick is in progress.
enum DraftTurn: Hashable {
    case ban
    case pick
}

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
    let turn: DraftTurn?
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
        if isMe { parts.append(String(localized: "Vos", table: "DesignSystem")) }
        switch role {
        case .assigned(let role): parts.append(String(localized: role.name))
        case .inferred(let role, let confidence):
            let percent = confidence.formatted(.percent.precision(.fractionLength(0)))
            parts.append(
                String(
                    localized: "Rol probable: \(String(localized: role.name)), \(percent)",
                    table: "DesignSystem"))
        case .uncertain(let role):
            parts.append(
                String(
                    localized: "Rol incierto, quizás \(String(localized: role.name))",
                    table: "DesignSystem"))
        case .none: break
        }
        switch pick {
        case .locked(let name):
            parts.append(String(localized: "\(name), lockeado", table: "DesignSystem"))
        case .hovering(let name):
            parts.append(String(localized: "\(name), en hover", table: "DesignSystem"))
        case .empty:
            parts.append(String(localized: "Sin campeón", table: "DesignSystem"))
        }
        switch turn {
        case .pick: parts.append(String(localized: "Eligiendo", table: "DesignSystem"))
        case .ban: parts.append(String(localized: "Baneando", table: "DesignSystem"))
        case nil: break
        }
        return parts.joined(separator: ", ")
    }
}

/// `TeamColumn(slots:side:)` of §22.3: one team's cells in a champ-select draft (§20.1).
struct TeamColumn: View {
    let slots: [DraftSlotRow]
    let side: TeamSide

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(slots) { row in
                    SlotRowView(row: row)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .draftAnimation(value: slots)
        } label: {
            Text(Self.title(side)).font(.headline)
        }
        .frame(minWidth: 200, idealWidth: 240, maxWidth: 280)
    }

    static func title(_ side: TeamSide) -> LocalizedStringResource {
        switch side {
        case .allies: LocalizedStringResource("Tu equipo", table: "DesignSystem")
        case .enemies: LocalizedStringResource("Equipo rival", table: "DesignSystem")
        }
    }
}

private struct SlotRowView: View {
    let row: DraftSlotRow

    var body: some View {
        HStack(spacing: 8) {
            // A new hover or lock pops in instead of swapping in place.
            ChampionIcon(id: row.champion, size: 28, state: row.iconState)
                .id(row.champion)
                .transition(.scale(scale: 0.85).combined(with: .opacity))
            PickLabel(pick: row.pick, isMe: row.isMe)
            Spacer(minLength: 4)
            if let turn = row.turn {
                TurnMarker(turn: turn)
            }
            RoleTag(role: row.role)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: row.accessibilityLabel))
    }
}

private struct PickLabel: View {
    let pick: DraftSlotRow.Pick
    let isMe: Bool

    var body: some View {
        HStack(spacing: 6) {
            switch pick {
            case .locked(let name):
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
                Text(verbatim: name)
                    .fontWeight(.semibold)
            case .hovering(let name):
                Image(systemName: "hand.point.up.left")
                    .foregroundStyle(.secondary)
                Text(verbatim: name)
                    .italic()
                    .foregroundStyle(.secondary)
            case .empty:
                Image(systemName: "circle.dotted")
                    .foregroundStyle(.tertiary)
                Text("Sin campeón", tableName: "DesignSystem")
                    .foregroundStyle(.secondary)
            }
            if isMe {
                Text("(vos)", tableName: "DesignSystem")
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
    }
}

private struct TurnMarker: View {
    let turn: DraftTurn

    var body: some View {
        Image(systemName: turn == .ban ? "nosign" : "hourglass")
            .foregroundStyle(Color.caution)
            .symbolEffect(.pulse)
            .help(
                turn == .ban
                    ? Text("Baneando", tableName: "DesignSystem")
                    : Text("Eligiendo", tableName: "DesignSystem"))
    }
}

/// Inferred roles carry a "?" and their probability; a guess without data says so.
private struct RoleTag: View {
    let role: DraftSlotRow.RoleLabel

    var body: some View {
        HStack(spacing: 2) {
            switch role {
            case .assigned(let role):
                Text(role.shortLabel)
            case .inferred(let role, let confidence):
                Text(role.shortLabel)
                Text(verbatim: "?")
                Text(confidence, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: confidence))
                    .foregroundStyle(.secondary)
            case .uncertain(let role):
                Image(systemName: "questionmark.circle")
                Text(role.shortLabel)
                Text("sin datos", tableName: "DesignSystem")
            case .none:
                EmptyView()
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(isUncertain ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        .fixedSize()
    }

    private var isUncertain: Bool {
        if case .uncertain = role { true } else { false }
    }
}

extension Role {
    /// The column abbreviation of §20.1.
    var shortLabel: LocalizedStringResource {
        switch self {
        case .top: LocalizedStringResource("TOP", table: "DesignSystem")
        case .jungle: LocalizedStringResource("JG", table: "DesignSystem")
        case .middle: LocalizedStringResource("MID", table: "DesignSystem")
        case .bottom: LocalizedStringResource("ADC", table: "DesignSystem")
        case .utility: LocalizedStringResource("SUP", table: "DesignSystem")
        }
    }

    var name: LocalizedStringResource {
        switch self {
        case .top: LocalizedStringResource("Top", table: "DesignSystem")
        case .jungle: LocalizedStringResource("Jungla", table: "DesignSystem")
        case .middle: LocalizedStringResource("Mid", table: "DesignSystem")
        case .bottom: LocalizedStringResource("Tirador", table: "DesignSystem")
        case .utility: LocalizedStringResource("Soporte", table: "DesignSystem")
        }
    }
}
