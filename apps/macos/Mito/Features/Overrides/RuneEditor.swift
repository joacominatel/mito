import MitoAssets
import MitoCore
import SwiftUI

/// The native rune editor (§21.5): one picker per row, rows found by their typed kind.
struct RuneEditor: View {
    @Binding var runes: RunePageDraft
    let gameData: GameData

    var body: some View {
        stylePicker(
            selection: Binding(
                get: { runes.primaryStyle },
                set: { runes.setPrimaryStyle($0, styles: styles) }),
            options: styles
        ) {
            Text("Rama principal", tableName: "Overrides")
        }
        if let primary = style(runes.primaryStyle) {
            PerkPicker(
                selection: $runes.keystone, perks: primary.rows(.keystone).first ?? [],
                gameData: gameData
            ) {
                Text("Runa clave", tableName: "Overrides")
            }
            ForEach(Array(primary.rows(.regular).prefix(3).enumerated()), id: \.offset) {
                index, row in
                PerkPicker(selection: $runes.primaryPerks[index], perks: row, gameData: gameData) {
                    Text("Principal, fila \(index + 1)", tableName: "Overrides")
                }
            }
        }
        stylePicker(
            selection: Binding(get: { runes.subStyle }, set: { runes.setSubStyle($0) }),
            options: styles.filter { $0.id != runes.primaryStyle }
        ) {
            Text("Rama secundaria", tableName: "Overrides")
        }
        if let sub = style(runes.subStyle) {
            ForEach(Array(sub.rows(.regular).enumerated()), id: \.offset) { index, row in
                PerkPicker(
                    selection: Binding(
                        get: { runes.secondaryPerk(inRow: index) },
                        set: { runes.setSecondaryPerk($0, inRow: index) }),
                    perks: row, gameData: gameData
                ) {
                    Text("Secundaria, fila \(index + 1)", tableName: "Overrides")
                }
            }
            Text(
                "Elegí dos runas secundarias de filas distintas; una tercera reemplaza a la más vieja.",
                tableName: "Overrides"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        if let primary = style(runes.primaryStyle) {
            ForEach(Array(primary.rows(.statMod).prefix(3).enumerated()), id: \.offset) {
                index, row in
                PerkPicker(selection: $runes.shards[index], perks: row, gameData: gameData) {
                    shardLabel(index)
                }
            }
        }
    }

    private var styles: [PerkStyle] { gameData.perkStyles }

    private func style(_ id: PerkStyleID?) -> PerkStyle? {
        id.flatMap(gameData.perkStyle)
    }

    private func shardLabel(_ index: Int) -> Text {
        switch index {
        case 0: Text("Fragmento de ataque", tableName: "Overrides")
        case 1: Text("Fragmento flexible", tableName: "Overrides")
        default: Text("Fragmento de defensa", tableName: "Overrides")
        }
    }

    private func stylePicker(
        selection: Binding<PerkStyleID?>, options: [PerkStyle], @ViewBuilder label: () -> Text
    ) -> some View {
        Picker(selection: selection) {
            Text("Ninguna", tableName: "Overrides").tag(PerkStyleID?.none)
            ForEach(options, id: \.id) { style in
                Text(style.name).tag(PerkStyleID?.some(style.id))
            }
        } label: {
            label()
        }
    }
}

private struct PerkPicker: View {
    @Binding var selection: PerkID?
    let perks: [PerkID]
    let gameData: GameData
    @ViewBuilder let label: () -> Text

    var body: some View {
        Picker(selection: $selection) {
            Text("Ninguna", tableName: "Overrides").tag(PerkID?.none)
            ForEach(perks, id: \.self) { perk in
                Text(gameData.overridesName(of: perk)).tag(PerkID?.some(perk))
            }
        } label: {
            label()
        }
    }
}
