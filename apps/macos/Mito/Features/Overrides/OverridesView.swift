import MitoAssets
import MitoCore
import SwiftUI

/// The "Overrides" destination (§21.5, §22.2); the shell builds it without arguments.
struct OverridesView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        OverridesScreen(model: app.overrides, gameData: app.clientData.gameData)
    }
}

struct OverridesScreen: View {
    let model: OverridesModel
    /// `nil` until the client's static data loads: nothing can be edited without it.
    let gameData: GameData?

    var body: some View {
        if let gameData {
            OverridesList(model: model, gameData: gameData)
        } else {
            NoClientDataView()
        }
    }
}

/// One list row, so the overrides and the champions share a single selection.
enum OverridesEntry: Hashable {
    case override(ChampionID, Role)
    case champion(ChampionID)
}

private struct OverridesList: View {
    @Bindable var model: OverridesModel
    let gameData: GameData
    @State private var selection: OverridesEntry?

    var body: some View {
        let overrides = model.listedOverrides(in: gameData)
        let champions = model.champions(in: gameData)
        List(selection: $selection) {
            if model.failure == .load {
                FailureLabel(failure: .load)
            }
            if !overrides.isEmpty {
                Section {
                    ForEach(overrides, id: \.entry) { override in
                        OverrideRow(
                            name: model.name(of: override.champion, in: gameData),
                            override: override
                        )
                        .tag(override.entry)
                    }
                } header: {
                    Text("Con overrides", tableName: "Overrides")
                }
            }
            Section {
                ForEach(champions, id: \.id) { champion in
                    Text(champion.name)
                        .tag(OverridesEntry.champion(champion.id))
                }
            } header: {
                Text("Campeones", tableName: "Overrides")
            }
        }
        .overlay {
            if overrides.isEmpty, champions.isEmpty, !model.searchText.isEmpty {
                ContentUnavailableView.search(text: model.searchText)
            }
        }
        .searchable(
            text: $model.searchText, prompt: Text("Buscar campeón", tableName: "Overrides")
        )
        .contextMenu(forSelectionType: OverridesEntry.self) { entries in
            if let entry = entries.first {
                Button {
                    open(entry)
                } label: {
                    Text("Editar…", tableName: "Overrides")
                }
            }
        } primaryAction: { entries in
            if let entry = entries.first { open(entry) }
        }
        .sheet(isPresented: $model.isEditing) {
            OverrideEditor(model: model, gameData: gameData)
        }
        .task { await model.load() }
    }

    private func open(_ entry: OverridesEntry) {
        switch entry {
        case .override(let champion, let role):
            model.open(champion, role: role, styles: gameData.perkStyles)
        case .champion(let champion):
            model.open(champion, styles: gameData.perkStyles)
        }
    }
}

extension ChampionOverride {
    fileprivate var entry: OverridesEntry { .override(champion, role) }
}

private struct OverrideRow: View {
    let name: String
    let override: ChampionOverride

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(name) · \(Text(override.role.overridesLabel))", tableName: "Overrides")
                Text(
                    "Runas: \(Text(override.runeMode.label)) · Spells: \(Text(override.spellMode.label)) · Ítems: \(Text(override.itemMode.label))",
                    tableName: "Overrides"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if override.isFavorite {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .help(Text("Favorito", tableName: "Overrides"))
                    .accessibilityLabel(Text("Favorito", tableName: "Overrides"))
            }
            if override.isExcludedFromPool {
                Image(systemName: "nosign")
                    .foregroundStyle(.secondary)
                    .help(Text("Excluido del pool", tableName: "Overrides"))
                    .accessibilityLabel(Text("Excluido del pool", tableName: "Overrides"))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A store failure, always with its icon.
struct FailureLabel: View {
    let failure: OverridesModel.Failure

    var body: some View {
        Label {
            switch failure {
            case .load: Text("No se pudieron leer los overrides.", tableName: "Overrides")
            case .save: Text("No se pudo guardar el override.", tableName: "Overrides")
            case .delete: Text("No se pudo eliminar el override.", tableName: "Overrides")
            }
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }
}

private struct NoClientDataView: View {
    var body: some View {
        ContentUnavailableView {
            Label {
                Text("Sin datos del cliente", tableName: "Overrides")
            } icon: {
                Image(systemName: "slider.horizontal.3")
            }
        } description: {
            Text(
                "Para editar los overrides, Mito necesita los campeones, runas, spells e ítems del cliente. Abrí League of Legends y vuelven a estar disponibles.",
                tableName: "Overrides")
        }
    }
}

extension Role {
    var overridesLabel: LocalizedStringResource {
        switch self {
        case .top: LocalizedStringResource("Top", table: "Overrides")
        case .jungle: LocalizedStringResource("Jungla", table: "Overrides")
        case .middle: LocalizedStringResource("Mid", table: "Overrides")
        case .bottom: LocalizedStringResource("ADC", table: "Overrides")
        case .utility: LocalizedStringResource("Support", table: "Overrides")
        }
    }
}

extension ChampionOverride.RuneMode {
    var label: LocalizedStringResource {
        switch self {
        case .adaptive: LocalizedStringResource("Adaptativo", table: "Overrides")
        case .general: LocalizedStringResource("General", table: "Overrides")
        case .fixed: LocalizedStringResource("Página fija", table: "Overrides")
        case .unknown: LocalizedStringResource("Desconocido", table: "Overrides")
        }
    }
}

extension ChampionOverride.SpellMode {
    var label: LocalizedStringResource {
        switch self {
        case .recommended: LocalizedStringResource("Recomendados", table: "Overrides")
        case .fixed: LocalizedStringResource("Fijos", table: "Overrides")
        case .unknown: LocalizedStringResource("Desconocido", table: "Overrides")
        }
    }
}

extension ChampionOverride.ItemMode {
    var label: LocalizedStringResource {
        switch self {
        case .recommended: LocalizedStringResource("Recomendados", table: "Overrides")
        case .fixedSet: LocalizedStringResource("Set fijo", table: "Overrides")
        case .skip: LocalizedStringResource("No importar", table: "Overrides")
        case .unknown: LocalizedStringResource("Desconocido", table: "Overrides")
        }
    }
}

extension GameData {
    /// Names in the client's locale, with the ID while one is missing.
    func overridesName(of perk: PerkID) -> String {
        if let name = self.perk(perk)?.name, !name.isEmpty { return name }
        return String(localized: "Runa \(perk.rawValue)", table: "Overrides")
    }

    func overridesName(of spell: SummonerSpellID) -> String {
        if let name = self.spell(spell)?.name, !name.isEmpty { return name }
        return String(localized: "Spell \(spell.rawValue)", table: "Overrides")
    }

    func overridesName(of item: ItemID) -> String {
        if let name = self.item(item)?.name, !name.isEmpty { return name }
        return String(localized: "Ítem \(String(item.rawValue))", table: "Overrides")
    }
}

#if DEBUG
    #Preview("Overrides") {
        OverridesScreen(model: .preview, gameData: .overridesPreview)
            .frame(width: 520, height: 480)
    }

    #Preview("Sin datos del cliente") {
        OverridesScreen(model: OverridesModel(), gameData: nil)
            .frame(width: 520, height: 480)
    }
#endif
