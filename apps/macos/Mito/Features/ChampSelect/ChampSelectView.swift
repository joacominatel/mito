import Foundation
import LCUKit
import MitoAssets
import MitoCore
import SwiftUI

/// The §20.1 draft: header, the two teams around the recommendations column, and the bans.
/// Renders nothing outside champ select.
struct ChampSelectView: View {
    let model: ChampSelectModel

    var body: some View {
        if let draft = model.draft {
            VStack(alignment: .leading, spacing: 16) {
                DraftHeader(
                    queue: draft.queue, phase: draft.phase, phaseInterval: model.phaseInterval,
                    isMyTurnToPick: draft.isMyTurnToPick, isMyTurnToBan: draft.isMyTurnToBan)
                HStack(alignment: .top, spacing: 16) {
                    TeamColumn(
                        title: Text("Tu equipo", tableName: "ChampSelect"), rows: model.allyRows)
                    RecommendationsPlaceholder()
                    TeamColumn(
                        title: Text("Equipo rival", tableName: "ChampSelect"), rows: model.enemyRows
                    )
                }
                BansRow(names: model.bannedNames)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

private struct DraftHeader: View {
    let queue: QueueType
    let phase: DraftPhase
    let phaseInterval: ClosedRange<Date>?
    let isMyTurnToPick: Bool
    let isMyTurnToBan: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(queue.label)
                .font(.title2.bold())
            Text(phase.label)
                .foregroundStyle(.secondary)
            Spacer()
            if let phaseInterval {
                Label {
                    Text(timerInterval: phaseInterval, countsDown: true)
                        .monospacedDigit()
                } icon: {
                    Image(systemName: "timer")
                }
                .accessibilityElement(children: .combine)
            }
            if isMyTurnToPick {
                TurnBadge(text: Text("Tu turno: elegir", tableName: "ChampSelect"))
            } else if isMyTurnToBan {
                TurnBadge(text: Text("Tu turno: banear", tableName: "ChampSelect"))
            }
        }
    }
}

private struct TurnBadge: View {
    let text: Text

    var body: some View {
        Label {
            text
        } icon: {
            Image(systemName: "hand.point.right.fill")
        }
        .font(.headline)
        .foregroundStyle(.tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.tint.quaternary, in: .capsule)
    }
}

private struct TeamColumn: View {
    let title: Text
    let rows: [DraftSlotRow]

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(rows) { row in
                    SlotRowView(row: row)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            title.font(.headline)
        }
        .frame(minWidth: 200, idealWidth: 240, maxWidth: 280)
    }
}

private struct SlotRowView: View {
    let row: DraftSlotRow

    var body: some View {
        HStack(spacing: 8) {
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
                Text("Sin campeón", tableName: "ChampSelect")
                    .foregroundStyle(.tertiary)
            }
            if isMe {
                Text("(vos)", tableName: "ChampSelect")
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
    }
}

private struct TurnMarker: View {
    let turn: ChampSelectModel.Turn

    var body: some View {
        Image(systemName: turn == .ban ? "nosign" : "hourglass")
            .foregroundStyle(.orange)
            .symbolEffect(.pulse)
            .help(
                turn == .ban
                    ? Text("Baneando", tableName: "ChampSelect")
                    : Text("Eligiendo", tableName: "ChampSelect"))
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
                    .foregroundStyle(.secondary)
            case .uncertain(let role):
                Image(systemName: "questionmark.circle")
                Text(role.shortLabel)
                Text("sin datos", tableName: "ChampSelect")
            case .none:
                EmptyView()
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(isUncertain ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
    }

    private var isUncertain: Bool {
        if case .uncertain = role { true } else { false }
    }
}

private struct RecommendationsPlaceholder: View {
    var body: some View {
        GroupBox {
            ContentUnavailableView {
                Label {
                    Text("Las recomendaciones van a aparecer acá", tableName: "ChampSelect")
                } icon: {
                    Image(systemName: "sparkles")
                }
            } description: {
                Text("Llegan con los datos del parche.", tableName: "ChampSelect")
            }
            .frame(maxWidth: .infinity, minHeight: 180)
        } label: {
            Text("Recomendados", tableName: "ChampSelect").font(.headline)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct BansRow: View {
    let names: [String]

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Label {
                Text("Bans", tableName: "ChampSelect")
            } icon: {
                Image(systemName: "nosign")
            }
            .font(.headline)
            if names.isEmpty {
                Text("Ninguno todavía", tableName: "ChampSelect")
                    .foregroundStyle(.secondary)
            } else {
                Text(names.formatted(.list(type: .and)))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: Previews

/// Sessions for the previews of this feature.
enum PreviewDraft {
    static let names = GameData(
        champions: [
            (266, "Aatrox"), (64, "Lee Sin"), (103, "Ahri"), (412, "Thresh"), (238, "Zed"),
            (157, "Yasuo"), (555, "Pyke"), (22, "Ashe"),
        ].map { Champion(id: ChampionID(rawValue: $0), alias: $1, name: $1, iconPath: "") })

    static func model(_ json: String, queue: QueueType) -> ChampSelectModel {
        let model = ChampSelectModel(connection: DisconnectedLCUConnection(), gameData: names)
        if let session = try? LCUEndpoint.champSelectSession.decode(Data(json.utf8)) {
            model.show(session, queue: queue, pickable: [])
        }
        return model
    }

    static let planning = """
        {"localPlayerCellId": 2,
         "myTeam": [
           {"cellId": 0, "assignedPosition": "top"},
           {"cellId": 1, "championPickIntent": 64, "assignedPosition": "jungle"},
           {"cellId": 2, "championPickIntent": 103, "assignedPosition": "middle"},
           {"cellId": 3, "assignedPosition": "bottom"},
           {"cellId": 4, "championPickIntent": 412, "assignedPosition": "utility"}],
         "theirTeam": [{"cellId": 5}, {"cellId": 6}, {"cellId": 7}, {"cellId": 8}, {"cellId": 9}],
         "timer": {"phase": "PLANNING", "adjustedTimeLeftInPhase": 29500}}
        """

    static let banPick = """
        {"localPlayerCellId": 2,
         "myTeam": [
           {"cellId": 0, "championId": 266, "assignedPosition": "top"},
           {"cellId": 1, "championId": 64, "assignedPosition": "jungle"},
           {"cellId": 2, "championId": 103, "assignedPosition": "middle"},
           {"cellId": 3, "assignedPosition": "bottom"},
           {"cellId": 4, "assignedPosition": "utility"}],
         "theirTeam": [{"cellId": 5, "championId": 238}, {"cellId": 6}, {"cellId": 7},
           {"cellId": 8}, {"cellId": 9}],
         "actions": [
           [{"actorCellId": 0, "championId": 157, "type": "ban", "completed": true},
            {"actorCellId": 5, "championId": 555, "type": "ban", "completed": true}],
           [{"actorCellId": 0, "championId": 266, "type": "pick", "completed": true}],
           [{"actorCellId": 5, "championId": 238, "type": "pick", "completed": true}],
           [{"actorCellId": 1, "championId": 64, "type": "pick", "isInProgress": true},
            {"actorCellId": 2, "championId": 103, "type": "pick", "isInProgress": true}]],
         "bans": {"myTeamBans": [157], "theirTeamBans": [555]},
         "timer": {"phase": "BAN_PICK", "adjustedTimeLeftInPhase": 27000}}
        """

    static let blind = """
        {"localPlayerCellId": 0,
         "myTeam": [{"cellId": 0}, {"cellId": 1, "championId": 22}, {"cellId": 2}],
         "theirTeam": [{"cellId": 5}, {"cellId": 6}],
         "actions": [[
           {"actorCellId": 0, "type": "pick", "isInProgress": true},
           {"actorCellId": 1, "championId": 22, "type": "pick", "completed": true}]],
         "timer": {"phase": "BAN_PICK", "adjustedTimeLeftInPhase": 81000}}
        """
}

#Preview("Planificación") {
    ChampSelectView(model: PreviewDraft.model(PreviewDraft.planning, queue: .rankedSolo))
        .frame(width: 900, height: 420)
}

#Preview("Bans y picks") {
    ChampSelectView(model: PreviewDraft.model(PreviewDraft.banPick, queue: .rankedSolo))
        .frame(width: 900, height: 420)
}

#Preview("Blind pick") {
    ChampSelectView(model: PreviewDraft.model(PreviewDraft.blind, queue: .normalBlind))
        .frame(width: 900, height: 420)
}
