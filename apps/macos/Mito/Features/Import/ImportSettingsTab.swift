import LCUKit
import MitoCore
import SwiftUI

/// §21.4.
struct ImportSettingsTab: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        let importing = $app.settings.importing
        let current = app.settings.importing
        Form {
            Section {
                Toggle(isOn: importing.importRunes) {
                    Text("Importar runas", tableName: "Import")
                }
                Picker(selection: importing.runeMode) {
                    Text("Adaptativo (según el matchup)", tableName: "Import")
                        .tag(ImportSettings.RuneMode.adaptive)
                    Text("General", tableName: "Import")
                        .tag(ImportSettings.RuneMode.general)
                    Text("Fijo por campeón", tableName: "Import")
                        .tag(ImportSettings.RuneMode.fixedPerChampion)
                } label: {
                    Text("Modo de runas", tableName: "Import")
                }
                .disabled(!current.importRunes)
                Picker(selection: importing.runePageTarget) {
                    Text("Página de Mito", tableName: "Import")
                        .tag(ImportSettings.RunePageTarget.mitoPage)
                    Text("Una página elegida", tableName: "Import")
                        .tag(ImportSettings.RunePageTarget.reservedPage)
                    Text("La página actual", tableName: "Import")
                        .tag(ImportSettings.RunePageTarget.currentPage)
                } label: {
                    Text("Página a usar", tableName: "Import")
                }
                .disabled(!current.importRunes)
                if current.runePageTarget == .reservedPage {
                    ReservedPagePicker(
                        selection: importing.reservedRunePageID, pages: app.importing.editablePages
                    )
                    .disabled(!current.importRunes)
                    .task { await app.importing.loadEditablePages() }
                }
            } header: {
                Text("Runas", tableName: "Import")
            }

            Section {
                Toggle(isOn: importing.importSpells) {
                    Text("Importar spells", tableName: "Import")
                }
                Picker(selection: importing.flashPosition) {
                    Text("D", tableName: "Import").tag(ImportSettings.FlashPosition.d)
                    Text("F", tableName: "Import").tag(ImportSettings.FlashPosition.f)
                    Text("Automática", tableName: "Import").tag(ImportSettings.FlashPosition.auto)
                } label: {
                    Text("Posición de Flash", tableName: "Import")
                }
                .disabled(!current.importSpells)
            } header: {
                Text("Spells", tableName: "Import")
            }

            Section {
                Toggle(isOn: importing.importItemSets) {
                    Text("Importar item sets", tableName: "Import")
                }
                Toggle(isOn: importing.cleanOldItemSets) {
                    Text("Limpiar sets viejos de Mito", tableName: "Import")
                }
                .disabled(!current.importItemSets)
            } header: {
                Text("Ítems", tableName: "Import")
            }

            Section {
                Toggle(isOn: importing.importOnHover) {
                    Text("Importar al hacer hover", tableName: "Import")
                }
                Toggle(isOn: importing.reimportOnOpponentChange) {
                    Text("Re-importar si cambia el rival", tableName: "Import")
                }
                Toggle(isOn: importing.preserveManualChanges) {
                    Text("No pisar cambios manuales", tableName: "Import")
                }
            } header: {
                Text("Cuándo importar", tableName: "Import")
            } footer: {
                Text(
                    "El modo adaptativo y el re-import llegan más adelante; por ahora el adaptativo importa la build general del parche.",
                    tableName: "Import"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// The page `RunePageTarget.reservedPage` overwrites, from the client's editable pages.
private struct ReservedPagePicker: View {
    @Binding var selection: Int?
    let pages: [PerkPage]

    var body: some View {
        Picker(selection: $selection) {
            Text("Ninguna", tableName: "Import").tag(Int?.none)
            ForEach(pages, id: \.id) { page in
                Text(verbatim: page.name ?? "#\(page.id)").tag(Int?.some(page.id))
            }
            if let selection, !pages.contains(where: { $0.id == selection }) {
                Text("Página \(String(selection)) (no está en el cliente)", tableName: "Import")
                    .tag(Int?.some(selection))
            }
        } label: {
            Text("Página", tableName: "Import")
        }
    }
}

#Preview {
    ImportSettingsTab()
        .environment(
            AppModel(
                connection: DisconnectedLCUConnection(),
                settings: SettingsModel(
                    value: MitoSettings(importing: ImportSettings(runePageTarget: .reservedPage))))
        )
        .frame(width: 520, height: 640)
}
