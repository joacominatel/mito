import MitoCore
import MitoEngine
import MitoImport
import SwiftUI

/// §22.4 quick toggles, bound to the same settings as the Settings tabs, plus a rune
/// replacement waiting on the user.
struct QuickTogglesMenuSection: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $app.settings.game.isAutoAcceptOn) {
                Text("Auto-accept", tableName: "Import")
            }
            Toggle(isOn: $app.settings.importing.importRunes) {
                Text("Importar runas", tableName: "Import")
            }
            Toggle(isOn: $app.settings.importing.importItemSets) {
                Text("Importar ítems", tableName: "Import")
            }
        }
        .toggleStyle(.checkbox)
        if let outcome = app.importing.outcome, outcome.needsConfirmation {
            PendingReplacementRow(
                outcome: outcome,
                confirm: { Task { await app.importing.confirmReplacement() } },
                decline: { app.importing.declineReplacement() })
        }
    }
}

private struct PendingReplacementRow: View {
    let outcome: ImportOutcome
    let confirm: () -> Void
    let decline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(outcome.headline)
            } icon: {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
            }
            if let runes = outcome.rows.first(where: { $0.part == .runes }) {
                Text(runes.status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button(action: decline) {
                    Text("Ahora no", tableName: "Import")
                }
                Button(action: confirm) {
                    Text("Reemplazar", tableName: "Import")
                }
            }
            .controlSize(.small)
        }
    }
}

#Preview("Toggles") {
    QuickTogglesMenuSection()
        .environment(AppModel(connection: DisconnectedLCUConnection()))
        .padding()
        .frame(width: 280)
}

#Preview("Confirmación pendiente") {
    PendingReplacementRow(
        outcome: ImportOutcome(
            id: 1, champion: ChampionID(rawValue: 103), title: "Ahri MID",
            report: ImportReport(
                runes: .needsConfirmation(pageID: 201, pageName: "My page"), spells: .applied,
                items: .applied),
            itemsUnavailable: nil),
        confirm: {}, decline: {}
    )
    .padding()
    .frame(width: 280)
}
