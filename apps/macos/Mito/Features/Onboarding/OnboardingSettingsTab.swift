import LCUKit
import MitoCore
import SwiftUI
import UniformTypeIdentifiers

/// §21.1, plus the pool by role (§19.1) and the Flash position (§21.4).
struct OnboardingSettingsTab: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        let general = $app.settings.general
        Form {
            Section {
                LoginItemRow(model: app.loginItem)
                Toggle(isOn: general.showWindowOnChampSelect) {
                    Text(GeneralSetting.showWindowOnChampSelect.title)
                }
                PresenceRows(presence: app.presence)
                Picker(selection: general.language) {
                    Text("Del sistema", tableName: "Onboarding")
                        .tag(GeneralSettings.Language.system)
                    Text(verbatim: "Español (Argentina)").tag(GeneralSettings.Language.spanish)
                    Text(verbatim: "English").tag(GeneralSettings.Language.english)
                } label: {
                    Text(GeneralSetting.language.title)
                }
                InstallPathRow(path: $app.leagueInstallPath)
            } header: {
                Text("General", tableName: "Onboarding")
            } footer: {
                Text(GeneralSetting.pendingFooter)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            UpdatesSection(updates: app.updates)

            PoolSection(model: app.onboarding)

            FlashSection(
                model: app.onboarding, position: $app.settings.importing.flashPosition)

            Section {
                Picker(selection: general.diamondPlusData) {
                    Text("Automático (según tu elo)", tableName: "Onboarding")
                        .tag(GeneralSettings.DiamondPlusData.auto)
                    Text("Activado", tableName: "Onboarding")
                        .tag(GeneralSettings.DiamondPlusData.on)
                    Text("Desactivado", tableName: "Onboarding")
                        .tag(GeneralSettings.DiamondPlusData.off)
                } label: {
                    Text(GeneralSetting.diamondPlusData.title)
                }
            } header: {
                Text("Datos", tableName: "Onboarding")
            } footer: {
                Text(
                    "Una capa sobre la base Esmeralda+. La descarga llega más adelante; por ahora Mito usa solo Esmeralda+.",
                    tableName: "Onboarding"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        // The user can change the login item in System Settings while Mito runs.
        .onAppear { app.loginItem.refresh() }
    }
}

private struct LoginItemRow: View {
    @Bindable var model: LoginItemModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: $model.launchesAtLogin) {
                Text(GeneralSetting.launchAtLogin.title)
            }
            .disabled(!model.isAvailable)
            if let note = model.note {
                note.view(openSystemSettings: model.openSystemSettings)
            }
        }
    }
}

extension LoginItemModel.Note {
    @ViewBuilder
    fileprivate func view(openSystemSettings: @escaping () -> Void) -> some View {
        switch self {
        case .unavailable:
            SettingNote(systemImage: "hammer") {
                Text(
                    "Los builds de desarrollo no se agregan a los ítems de inicio.",
                    tableName: "Onboarding")
            }
        case .requiresApproval:
            HStack {
                SettingNote(systemImage: "exclamationmark.triangle") {
                    Text(
                        "Falta permitirlo en Configuración del Sistema.",
                        tableName: "Onboarding")
                }
                Button(action: openSystemSettings) {
                    Text("Abrir…", tableName: "Onboarding")
                }
                .controlSize(.small)
            }
        case .failed:
            SettingNote(systemImage: "exclamationmark.triangle") {
                Text("No se pudo cambiar el ítem de inicio.", tableName: "Onboarding")
            }
        }
    }
}

private struct PresenceRows: View {
    @Bindable var presence: AppPresenceModel

    var body: some View {
        Toggle(isOn: $presence.showsMenuBarIcon) {
            Text(GeneralSetting.showMenuBarIcon.title)
        }
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: $presence.showsDockIcon) {
                Text(GeneralSetting.showDockIcon.title)
            }
            .disabled(!presence.canHideDockIcon)
            if !presence.canHideDockIcon {
                SettingNote(systemImage: "info.circle") {
                    Text(
                        "Sin el ícono de la barra de menú, Mito queda en el Dock para que siempre puedas abrirlo.",
                        tableName: "Onboarding")
                }
            }
        }
    }
}

/// A short secondary line under a row; never an alert.
private struct SettingNote<Content: View>: View {
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        Label {
            content
        } icon: {
            Image(systemName: systemImage)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}

private struct UpdatesSection: View {
    @Bindable var updates: UpdaterModel

    var body: some View {
        Section {
            Toggle(isOn: $updates.automaticallyChecksForUpdates) {
                Text("Buscar actualizaciones automáticamente", tableName: "Onboarding")
            }
            Toggle(isOn: $updates.receivesBetaUpdates) {
                Text("Recibir versiones beta", tableName: "Onboarding")
            }
        } header: {
            Text("Actualizaciones", tableName: "Onboarding")
        } footer: {
            Group {
                if updates.isConfigured {
                    Text(
                        "Las betas llegan antes y pueden tener errores.", tableName: "Onboarding")
                } else {
                    Label {
                        Text(
                            "Las actualizaciones todavía no están configuradas en esta versión.",
                            tableName: "Onboarding")
                    } icon: {
                        Image(systemName: "info.circle")
                    }
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .disabled(!updates.isConfigured)
    }
}

private struct InstallPathRow: View {
    @Binding var path: String?
    @State private var isChoosing = false

    var body: some View {
        LabeledContent {
            HStack {
                if let path {
                    Text(verbatim: path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(path)
                    Button {
                        self.path = nil
                    } label: {
                        Text("Detectar sola", tableName: "Onboarding")
                    }
                } else {
                    Text("Automática", tableName: "Onboarding")
                        .foregroundStyle(.secondary)
                }
                Button {
                    isChoosing = true
                } label: {
                    Text("Elegir…", tableName: "Onboarding")
                }
            }
        } label: {
            Text(GeneralSetting.leagueInstallPath.title)
        }
        .fileImporter(isPresented: $isChoosing, allowedContentTypes: [.applicationBundle, .folder])
        {
            if case .success(let url) = $0 { path = url.path(percentEncoded: false) }
        }
    }
}

private struct PoolSection: View {
    @Bindable var model: OnboardingModel
    @State private var isAdding = false

    var body: some View {
        Section {
            Picker(selection: $model.role) {
                ForEach(Role.allCases, id: \.self) { role in
                    Text(role.title).tag(role)
                }
            } label: {
                Text("Rol", tableName: "Onboarding")
            }
            .pickerStyle(.segmented)

            ForEach(Array(model.pool.enumerated()), id: \.element) { index, champion in
                PoolRow(
                    position: index + 1, name: model.name(of: champion),
                    isFirst: index == 0, isLast: index == model.pool.count - 1,
                    moveUp: { Task { await model.moveUp(champion) } },
                    moveDown: { Task { await model.moveDown(champion) } },
                    remove: { Task { await model.remove(champion) } }
                )
                .disabled(!model.canEditPool)
            }

            if model.pool.isEmpty && model.canEditPool {
                Text("Todavía no elegiste campeones para este rol.", tableName: "Onboarding")
                    .foregroundStyle(.secondary)
            }

            Button {
                isAdding = true
            } label: {
                Label {
                    Text("Agregar campeón…", tableName: "Onboarding")
                } icon: {
                    Image(systemName: "plus")
                }
            }
            .disabled(!model.canAddToPool)
            .popover(isPresented: $isAdding, arrowEdge: .trailing) {
                ChampionPicker(model: model) { isAdding = false }
            }
        } header: {
            Text("Pool de campeones", tableName: "Onboarding")
        } footer: {
            PoolFooter(problem: model.poolProblem, catalog: model.catalog)
        }
        .task(id: model.role) { await model.loadPool() }
    }
}

private struct PoolRow: View {
    let position: Int
    let name: String
    let isFirst: Bool
    let isLast: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack {
            Text(position, format: .number)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Text(verbatim: name)
            if isFirst {
                Text("Principal", tableName: "Onboarding")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: moveUp) {
                Image(systemName: "chevron.up")
            }
            .disabled(isFirst)
            .accessibilityLabel(Text("Subir \(name)", tableName: "Onboarding"))
            Button(action: moveDown) {
                Image(systemName: "chevron.down")
            }
            .disabled(isLast)
            .accessibilityLabel(Text("Bajar \(name)", tableName: "Onboarding"))
            Button(action: remove) {
                Image(systemName: "minus.circle")
            }
            .accessibilityLabel(Text("Quitar \(name)", tableName: "Onboarding"))
        }
        .buttonStyle(.borderless)
        .accessibilityElement(children: .contain)
    }
}

private struct PoolFooter: View {
    let problem: OnboardingModel.PoolProblem?
    let catalog: OnboardingModel.Loading<[Champion]>

    var body: some View {
        Group {
            switch (problem, catalog) {
            case (.readFailed, _):
                warning(Text("No se pudo leer tu pool.", tableName: "Onboarding"))
            case (.saveFailed, _):
                warning(Text("No se pudo guardar el último cambio.", tableName: "Onboarding"))
            case (nil, .unavailable):
                Label {
                    Text(
                        "Abrí el cliente de League para elegir campeones: la lista sale de sus datos.",
                        tableName: "Onboarding")
                } icon: {
                    Image(systemName: "bolt.horizontal.circle")
                }
            case (nil, _):
                Text(
                    "El primero de cada rol es tu principal.",
                    tableName: "Onboarding")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    private func warning(_ text: Text) -> some View {
        Label {
            text
        } icon: {
            Image(systemName: "exclamationmark.triangle")
        }
    }
}

private struct ChampionPicker: View {
    @Bindable var model: OnboardingModel
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(text: $model.query) {
                Text("Buscar campeón", tableName: "Onboarding")
            }
            .textFieldStyle(.roundedBorder)
            List(model.searchResults, id: \.id) { champion in
                Button {
                    Task { await model.add(champion.id) }
                    model.query = ""
                    done()
                } label: {
                    Text(verbatim: champion.name)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Agregar \(champion.name)", tableName: "Onboarding"))
            }
            .listStyle(.plain)
        }
        .padding()
        .frame(width: 240, height: 320)
    }
}

private struct FlashSection: View {
    let model: OnboardingModel
    @Binding var position: ImportSettings.FlashPosition

    var body: some View {
        Section {
            Picker(selection: $position) {
                Text("D", tableName: "Onboarding").tag(ImportSettings.FlashPosition.d)
                Text("F", tableName: "Onboarding").tag(ImportSettings.FlashPosition.f)
                Text("Automática", tableName: "Onboarding").tag(ImportSettings.FlashPosition.auto)
            } label: {
                Text("Posición de Flash", tableName: "Onboarding")
            }
            Label {
                Text(model.flashSummary)
            } icon: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .foregroundStyle(.secondary)
        } header: {
            Text("Flash", tableName: "Onboarding")
        } footer: {
            Text(
                "Con «Automática», Mito usa la posición detectada en tus últimas \(OnboardingModel.flashSample) partidas.",
                tableName: "Onboarding"
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }
}

extension Role {
    fileprivate var title: LocalizedStringResource {
        switch self {
        case .top: LocalizedStringResource("Top", table: "Onboarding")
        case .jungle: LocalizedStringResource("Jungla", table: "Onboarding")
        case .middle: LocalizedStringResource("Mid", table: "Onboarding")
        case .bottom: LocalizedStringResource("Tirador", table: "Onboarding")
        case .utility: LocalizedStringResource("Soporte", table: "Onboarding")
        }
    }
}

#if DEBUG
    #Preview("Pool lleno") {
        let app = AppModel.onboardingPreview
        OnboardingSettingsTab()
            .environment(app)
            .frame(width: 520, height: 720)
            .task { await app.clientData.run() }
            .task { await app.onboarding.run() }
    }
#endif

#Preview("Sin datos") {
    OnboardingSettingsTab()
        .environment(AppModel(connection: DisconnectedLCUConnection()))
        .frame(width: 520, height: 720)
}
