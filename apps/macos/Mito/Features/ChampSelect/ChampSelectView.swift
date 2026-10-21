import Foundation
import LCUKit
import MitoAssets
import MitoCore
import MitoEngine
import SwiftUI

/// The §20.1 draft: header, the two teams around the recommendations column, the bans, and the
/// analysis panel. Renders nothing outside champ select.
struct ChampSelectView: View {
    @Environment(AppModel.self) private var app

    let model: ChampSelectModel

    var body: some View {
        if let draft = model.draft {
            VStack(alignment: .leading, spacing: 16) {
                DraftHeader(
                    queue: draft.queue, phase: draft.phase, phaseInterval: model.phaseInterval,
                    isMyTurnToPick: draft.isMyTurnToPick, isMyTurnToBan: draft.isMyTurnToBan)
                HStack(alignment: .top, spacing: 16) {
                    TeamColumn(slots: model.allyRows, side: .allies)
                    if let list = model.recommendations {
                        // Widest first: the team columns keep their minimum, the picks get the rest.
                        RecommendationsColumn(
                            list: list, role: model.scoringRole,
                            roleSelection: model.canChooseRole ? roleSelection : nil,
                            names: model.reasonNames
                        )
                        .layoutPriority(1)
                    }
                    TeamColumn(slots: model.enemyRows, side: .enemies)
                }
                // The draft takes what it needs first; the panel gets the rest, down to its minimum.
                .layoutPriority(1)
                BansRow(bans: model.bans)
                AnalysisPanel(model: app.analysis)
            }
            .draftAnimation(value: draft)
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var roleSelection: Binding<Role> {
        Binding(get: { model.scoringRole ?? .middle }, set: model.chooseRole)
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
                        .contentTransition(.numericText(countsDown: true))
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

private struct BansRow: View {
    let bans: [BannedChampion]

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Label {
                Text("Bans", tableName: "ChampSelect")
            } icon: {
                Image(systemName: "nosign")
            }
            .font(.headline)
            if bans.isEmpty {
                Text("Ninguno todavía", tableName: "ChampSelect")
                    .foregroundStyle(.secondary)
            } else {
                // Ten names do not fit a narrow window: then only the icons, named on hover.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        ForEach(Array(bans.enumerated()), id: \.offset) { _, ban in
                            HStack(spacing: 4) {
                                ChampionIcon(id: ban.id, size: 20, state: .banned)
                                    .alignmentGuide(.firstTextBaseline) { $0.height * 0.75 }
                                Text(verbatim: ban.name)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        ForEach(Array(bans.enumerated()), id: \.offset) { _, ban in
                            ChampionIcon(id: ban.id, size: 20, state: .banned, label: ban.name)
                                .alignmentGuide(.firstTextBaseline) { $0.height * 0.75 }
                                .help(Text(verbatim: ban.name))
                        }
                    }
                }
            }
            Spacer(minLength: 0)
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
        .environment(AppModel(connection: DisconnectedLCUConnection()))
}

#Preview("Bans y picks") {
    ChampSelectView(model: PreviewDraft.model(PreviewDraft.banPick, queue: .rankedSolo))
        .frame(width: 900, height: 420)
        .environment(AppModel(connection: DisconnectedLCUConnection()))
}

#Preview("Blind pick") {
    ChampSelectView(model: PreviewDraft.model(PreviewDraft.blind, queue: .normalBlind))
        .frame(width: 900, height: 420)
        .environment(AppModel(connection: DisconnectedLCUConnection()))
}
