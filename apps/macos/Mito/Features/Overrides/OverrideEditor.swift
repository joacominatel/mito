import MitoAssets
import MitoCore
import SwiftUI

/// The sheet for one (champion, role): Cancel discards, Save stores (§21.5).
struct OverrideEditor: View {
    @Bindable var model: OverridesModel
    let gameData: GameData
    @State private var isConfirmingDelete = false

    var body: some View {
        if let draft = Binding($model.draft) {
            Form {
                header(draft)
                pool(draft)
                runes(draft)
                spells(draft)
                items(draft)
                if let failure = model.failure, failure != .load {
                    FailureLabel(failure: failure)
                }
            }
            .formStyle(.grouped)
            .frame(minWidth: 520, idealWidth: 560, minHeight: 560, idealHeight: 680)
            .toolbar { actions }
            .confirmationDialog(
                Text("¿Eliminar este override?", tableName: "Overrides"),
                isPresented: $isConfirmingDelete
            ) {
                Button(role: .destructive) {
                    Task { await model.delete() }
                } label: {
                    Text("Eliminar", tableName: "Overrides")
                }
            } message: {
                Text(
                    "Mito vuelve a usar la configuración general para este campeón en este rol.",
                    tableName: "Overrides")
            }
        }
    }

    private var styles: [PerkStyle] { gameData.perkStyles }

    @ToolbarContentBuilder
    private var actions: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button {
                model.close()
            } label: {
                Text("Cancelar", tableName: "Overrides")
            }
        }
        if model.isStored {
            ToolbarItem(placement: .destructiveAction) {
                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    Text("Eliminar override", tableName: "Overrides")
                }
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button {
                Task { await model.save(styles: styles) }
            } label: {
                Text("Guardar", tableName: "Overrides")
            }
            .disabled(!model.canSave(styles: styles))
        }
    }

    private func header(_ draft: Binding<OverrideDraft>) -> some View {
        Section {
            Picker(
                selection: Binding(
                    get: { draft.wrappedValue.role },
                    set: { model.switchRole(to: $0, styles: styles) })
            ) {
                ForEach(Role.allCases, id: \.self) { role in
                    Text(role.overridesLabel).tag(role)
                }
            } label: {
                Text("Rol", tableName: "Overrides")
            }
            .pickerStyle(.segmented)
            .disabled(model.hasChanges)
        } header: {
            Text(model.name(of: draft.wrappedValue.champion, in: gameData))
                .font(.title2.bold())
        } footer: {
            if model.hasChanges {
                Text(
                    "Guardá o cancelá los cambios para pasar a otro rol.", tableName: "Overrides"
                )
                .foregroundStyle(.secondary)
            }
        }
    }

    private func pool(_ draft: Binding<OverrideDraft>) -> some View {
        Section {
            Toggle(isOn: draft.isFavorite) {
                Text("Favorito", tableName: "Overrides")
            }
            Toggle(isOn: draft.isExcludedFromPool) {
                Text("Excluir del pool", tableName: "Overrides")
            }
        } header: {
            Text("Pool", tableName: "Overrides")
        }
    }

    private func runes(_ draft: Binding<OverrideDraft>) -> some View {
        Section {
            Picker(selection: draft.runeMode) {
                ForEach(
                    [ChampionOverride.RuneMode.adaptive, .general, .fixed], id: \.rawValue
                ) { mode in
                    Text(mode.label).tag(mode)
                }
            } label: {
                Text("Modo de runas", tableName: "Overrides")
            }
            if draft.wrappedValue.runeMode == .fixed {
                RuneEditor(runes: draft.runes, gameData: gameData)
                IssueLabels(issues: model.issues(styles: styles).filter(\.isAboutRunes))
            }
        } header: {
            Text("Runas", tableName: "Overrides")
        }
    }

    private func spells(_ draft: Binding<OverrideDraft>) -> some View {
        Section {
            Picker(selection: draft.spellMode) {
                ForEach([ChampionOverride.SpellMode.recommended, .fixed], id: \.rawValue) {
                    mode in
                    Text(mode.label).tag(mode)
                }
            } label: {
                Text("Modo de spells", tableName: "Overrides")
            }
            if draft.wrappedValue.spellMode == .fixed {
                SpellPairEditor(
                    spells: draft.spells, options: model.classicSpells(in: gameData),
                    gameData: gameData)
                IssueLabels(issues: model.issues(styles: styles).filter { $0 == .incompleteSpells })
            }
        } header: {
            Text("Spells", tableName: "Overrides")
        }
    }

    private func items(_ draft: Binding<OverrideDraft>) -> some View {
        Section {
            Picker(selection: draft.itemMode) {
                ForEach(
                    [ChampionOverride.ItemMode.recommended, .fixedSet, .skip], id: \.rawValue
                ) { mode in
                    Text(mode.label).tag(mode)
                }
            } label: {
                Text("Modo de ítems", tableName: "Overrides")
            }
            if draft.wrappedValue.itemMode == .fixedSet {
                ItemSetEditor(model: model, items: draft.items, gameData: gameData)
                IssueLabels(issues: model.issues(styles: styles).filter { $0 == .emptyItemSet })
            }
        } header: {
            Text("Ítems", tableName: "Overrides")
        }
    }
}

extension OverrideIssue {
    fileprivate var isAboutRunes: Bool {
        switch self {
        case .incompleteRunePage, .invalidRunePage: true
        case .incompleteSpells, .emptyItemSet: false
        }
    }
}

private struct IssueLabels: View {
    let issues: [OverrideIssue]

    var body: some View {
        ForEach(issues.indices, id: \.self) { index in
            Label {
                text(for: issues[index])
            } icon: {
                Image(systemName: "exclamationmark.circle")
            }
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func text(for issue: OverrideIssue) -> some View {
        switch issue {
        case .incompleteRunePage:
            Text("Completá la página para poder guardarla.", tableName: "Overrides")
        case .invalidRunePage:
            Text(
                "La página no es válida para el parche actual. Revisá cada fila.",
                tableName: "Overrides")
        case .incompleteSpells:
            Text("Elegí dos spells distintos.", tableName: "Overrides")
        case .emptyItemSet:
            Text("Agregá al menos un ítem al set.", tableName: "Overrides")
        }
    }
}

private struct SpellPairEditor: View {
    @Binding var spells: SpellDraft
    /// Summoner's Rift spells only.
    let options: [SummonerSpell]
    let gameData: GameData

    var body: some View {
        picker(selection: $spells.first, excluding: spells.second) {
            Text("Primer spell", tableName: "Overrides")
        }
        picker(selection: $spells.second, excluding: spells.first) {
            Text("Segundo spell", tableName: "Overrides")
        }
    }

    private func picker(
        selection: Binding<SummonerSpellID?>, excluding other: SummonerSpellID?,
        @ViewBuilder label: () -> Text
    ) -> some View {
        Picker(selection: selection) {
            Text("Ninguno", tableName: "Overrides").tag(SummonerSpellID?.none)
            ForEach(options.filter { $0.id != other }, id: \.id) { spell in
                Text(gameData.overridesName(of: spell.id)).tag(SummonerSpellID?.some(spell.id))
            }
        } label: {
            label()
        }
    }
}
