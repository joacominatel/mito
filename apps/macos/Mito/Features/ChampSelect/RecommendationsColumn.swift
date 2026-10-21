import MitoCore
import SwiftUI

/// The center column of §20.1: the top picks, or the bans during the ban phase, with their
/// reasons, and the controls that move them. Suggestions only (§5).
struct RecommendationsColumn: View {
    let list: RecommendationList
    let role: Role?
    /// Only in blind pick, where the user picks the role to score for (§20.3).
    var roleSelection: Binding<Role>?
    let names: ReasonNames

    static let reasonsShown = 3

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                if let roleSelection {
                    RolePicker(selection: roleSelection)
                }
                RecommendationContent(list: list, names: names)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                // The slider and the mode move picks only.
                if !list.isBans {
                    Divider()
                    RecommendationControls()
                }
            }
        } label: {
            title.font(.headline)
        }
        .frame(maxWidth: .infinity)
    }

    private var title: Text {
        guard let role else {
            return Text("Recomendados", tableName: "ChampSelect")
        }
        let label = String(localized: role.shortLabel)
        return list.isBans
            ? Text("Bans recomendados (\(label))", tableName: "ChampSelect")
            : Text("Recomendados para vos (\(label))", tableName: "ChampSelect")
    }
}

private struct RecommendationContent: View {
    let list: RecommendationList
    let names: ReasonNames

    var body: some View {
        if case .unavailable(let reason) = list {
            UnavailableRecommendations(reason: reason)
        } else if list.rows.isEmpty {
            NoCandidates()
        } else {
            RankedList(rows: list.rows, names: names)
        }
    }
}

private struct RankedList: View {
    let rows: [RecommendationList.Row]
    let names: ReasonNames

    var body: some View {
        // Scrolls only when the list outgrows the column.
        ViewThatFits(in: .vertical) {
            list
            // Clear of a legacy scroller.
            ScrollView { list.padding(.trailing, 16) }
        }
        .frame(maxHeight: 360, alignment: .top)
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        ChampionIcon(id: row.id, size: 24)
                            .alignmentGuide(.firstTextBaseline) { $0.height * 0.75 }
                        Text(verbatim: "\(index + 1). \(names.champion(row.id))")
                            .font(.body.weight(.semibold))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if let score = row.score {
                            DeltaBadge(delta: score)
                                .fixedSize()
                                .accessibilityHidden(true)
                            // Reads the score and its confidence for the row.
                            WinrateBar(value: score, baseline: 0, confidence: row.confidence)
                                .frame(width: 80)
                        }
                        ConfidenceIndicator(level: row.confidence)
                            .fixedSize()
                            .accessibilityHidden(row.score != nil)
                    }
                    .accessibilityElement(children: .combine)
                    ForEach(
                        Array(row.reasons.prefix(RecommendationsColumn.reasonsShown).enumerated()),
                        id: \.offset
                    ) { _, reason in
                        ReasonRow(reason: reason, names: names)
                            .padding(.leading, 16)
                    }
                }
            }
        }
    }
}

private struct NoCandidates: View {
    var body: some View {
        ContentUnavailableView {
            Label {
                Text("Ningún candidato", tableName: "ChampSelect")
            } icon: {
                Image(systemName: "person.crop.circle.badge.questionmark")
            }
        } description: {
            Text(
                "Probá con otro modo de candidatos, o sumá campeones a tu pool.",
                tableName: "ChampSelect")
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }
}

private struct UnavailableRecommendations: View {
    let reason: RecommendationList.Unavailable

    var body: some View {
        ContentUnavailableView {
            switch reason {
            case .noSnapshot:
                Label {
                    Text("Sin estadísticas todavía", tableName: "ChampSelect")
                } icon: {
                    Image(systemName: "chart.bar.xaxis")
                }
            case .noRole:
                Label {
                    Text("Sin rol asignado", tableName: "ChampSelect")
                } icon: {
                    Image(systemName: "questionmark.circle")
                }
            case .disabled:
                Label {
                    Text("Recomendaciones apagadas", tableName: "ChampSelect")
                } icon: {
                    Image(systemName: "eye.slash")
                }
            }
        } description: {
            switch reason {
            case .noSnapshot:
                Text(
                    "Las recomendaciones llegan con los datos del parche.", tableName: "ChampSelect"
                )
            case .noRole:
                Text(
                    "Sin rol no hay contra quién comparar los campeones.", tableName: "ChampSelect")
            case .disabled:
                Text(
                    "Se prenden en Settings, pestaña Champ select.", tableName: "ChampSelect")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }
}

private struct RolePicker: View {
    @Binding var selection: Role

    var body: some View {
        Picker(selection: $selection) {
            ForEach(Role.allCases, id: \.self) { role in
                Text(role.shortLabel)
                    .accessibilityLabel(Text(role.name))
                    .tag(role)
            }
        } label: {
            Text("Rol", tableName: "ChampSelect")
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .fixedSize()
        .help(Text("Sin rol asignado: elegí para qué rol recomendar", tableName: "ChampSelect"))
    }
}

/// The Meta ↔ Comfort slider and the candidate mode, written straight to the settings (§18.3).
private struct RecommendationControls: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        VStack(alignment: .leading, spacing: 8) {
            Slider(value: $app.settings.champSelect.metaComfortBalance, in: 0...1) {
                Text("Meta o comfort", tableName: "ChampSelect")
            } minimumValueLabel: {
                Text("Meta", tableName: "ChampSelect")
            } maximumValueLabel: {
                Text("Comfort", tableName: "ChampSelect")
            }
            .labelsHidden()
            CandidatesPicker(selection: $app.settings.champSelect.candidates)
                .fixedSize()
        }
        .font(.callout)
    }
}

struct CandidatesPicker: View {
    @Binding var selection: ChampSelectSettings.Candidates

    var body: some View {
        Picker(selection: $selection) {
            Text("Mi pool", tableName: "ChampSelect").tag(ChampSelectSettings.Candidates.myPool)
            Text("Campeones que tengo", tableName: "ChampSelect")
                .tag(ChampSelectSettings.Candidates.owned)
            Text("Todos", tableName: "ChampSelect").tag(ChampSelectSettings.Candidates.all)
        } label: {
            Text("Candidatos", tableName: "ChampSelect")
        }
    }
}

// MARK: Previews

enum PreviewRecommendations {
    static let picks: RecommendationList = .picks([
        PickRecommendation(
            champion: ChampionID(rawValue: 103), score: 0.038, components: [:],
            reasons: [
                Reason(
                    kind: .matchup(opponent: ChampionID(rawValue: 238), delta: 0.021, games: 8212),
                    sample: .reliable),
                Reason(kind: .fillsDamageGap(adds: .magic, alliedShare: 0.78), sample: .reliable),
                Reason(kind: .meta(tier: .a, games: 2824), sample: .reliable),
            ],
            confidence: .reliable),
        PickRecommendation(
            champion: ChampionID(rawValue: 99), score: 0.031, components: [:],
            reasons: [
                Reason(
                    kind: .synergy(
                        ally: ChampionID(rawValue: 64), allyRole: .jungle, delta: 0.014,
                        games: 96),
                    sample: .usable),
                Reason(
                    kind: .matchup(opponent: ChampionID(rawValue: 238), delta: -0.006, games: 427),
                    sample: .reliable),
            ],
            confidence: .reliable),
        PickRecommendation(
            champion: ChampionID(rawValue: 90), score: -0.004, components: [:],
            reasons: [Reason(kind: .meta(tier: .c, games: 640), sample: .usable)],
            confidence: .usable),
    ])

    static let bans: RecommendationList = .bans([
        BanRecommendation(
            champion: ChampionID(rawValue: 90), score: 0.012, components: [:],
            reasons: [
                Reason(
                    kind: .threatens(pick: ChampionID(rawValue: 103), delta: -0.042, games: 456),
                    sample: .reliable),
                Reason(
                    kind: .threatens(pick: ChampionID(rawValue: 99), delta: -0.031, games: 120),
                    sample: .usable),
            ],
            confidence: .reliable)
    ])
}

#Preview("Picks con razones") {
    RecommendationsColumn(list: PreviewRecommendations.picks, role: .middle, names: .preview)
        .environment(AppModel(connection: DisconnectedLCUConnection()))
        .frame(width: 460)
        .padding()
}

#Preview("Blind pick con selector de rol") {
    @Previewable @State var role = Role.middle
    RecommendationsColumn(
        list: PreviewRecommendations.picks, role: role, roleSelection: $role, names: .preview
    )
    .environment(AppModel(connection: DisconnectedLCUConnection()))
    .frame(width: 460)
    .padding()
}

#Preview("Fase de bans") {
    RecommendationsColumn(list: PreviewRecommendations.bans, role: .middle, names: .preview)
        .environment(AppModel(connection: DisconnectedLCUConnection()))
        .frame(width: 460)
        .padding()
}

#Preview("Sin snapshot") {
    RecommendationsColumn(list: .unavailable(.noSnapshot), role: .middle, names: .ids)
        .environment(AppModel(connection: DisconnectedLCUConnection()))
        .frame(width: 460)
        .padding()
}
