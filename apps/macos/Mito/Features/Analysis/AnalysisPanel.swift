import MitoCore
import SwiftUI

/// The §20.1 "Análisis" panel: a tab picker over the tab the user chose. Renders nothing
/// outside champ select.
struct AnalysisPanel: View {
    @Bindable var model: AnalysisModel

    var body: some View {
        if let subject = model.subject {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    TabPicker(selection: $model.tab)
                    ScrollView {
                        content(for: subject)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
                .frame(
                    maxWidth: .infinity, minHeight: 220, maxHeight: .infinity,
                    alignment: .topLeading)
            } label: {
                Text("Análisis", tableName: "Analysis").font(.headline)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Análisis", tableName: "Analysis"))
        }
    }

    @ViewBuilder
    private func content(for subject: AnalysisSubject) -> some View {
        if model.isMissingSnapshot {
            NoSnapshot()
        } else {
            switch model.tab {
            case .matchup: MatchupTab(subject: subject)
            case .composition: CompositionTab(subject: subject)
            case .build: BuildTab(subject: subject)
            case .history: HistoryTab(subject: subject)
            }
        }
    }
}

private struct TabPicker: View {
    @Binding var selection: AnalysisModel.Tab

    var body: some View {
        Picker(selection: $selection) {
            ForEach(AnalysisModel.Tab.allCases, id: \.self) { tab in
                Text(tab.title).tag(tab)
            }
        } label: {
            Text("Pestaña del análisis", tableName: "Analysis")
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }
}

private struct NoSnapshot: View {
    var body: some View {
        ContentUnavailableView {
            Label {
                Text("Sin estadísticas todavía", tableName: "Analysis")
            } icon: {
                Image(systemName: "chart.bar.xaxis")
            }
        } description: {
            Text("El análisis llega con los datos del parche.", tableName: "Analysis")
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }
}

extension AnalysisModel.Tab {
    var title: LocalizedStringResource {
        switch self {
        case .matchup: LocalizedStringResource("Matchup", table: "Analysis")
        case .composition: LocalizedStringResource("Composición", table: "Analysis")
        case .build: LocalizedStringResource("Build", table: "Analysis")
        case .history: LocalizedStringResource("Mi historial", table: "Analysis")
        }
    }
}

// MARK: Previews

#Preview("Sin snapshot") {
    AnalysisPanel(
        model: AnalysisModel(
            champSelect: PreviewDraft.model(PreviewDraft.banPick, queue: .rankedSolo))
    )
    .padding()
    .frame(width: 900)
}

#Preview("Mi historial") {
    let model = AnalysisModel(
        champSelect: PreviewDraft.model(PreviewDraft.banPick, queue: .rankedSolo))
    model.tab = .history
    return AnalysisPanel(model: model)
        .padding()
        .frame(width: 900)
}
