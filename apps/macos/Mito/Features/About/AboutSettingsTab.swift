import AppKit
import MitoCore
import SwiftUI

/// The "Acerca de" Settings tab; the shell builds it without arguments.
struct AboutSettingsTab: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        AboutScreen(meta: app.snapshots.meta, info: Bundle.main.infoDictionary)
    }
}

struct AboutScreen: View {
    let meta: SnapshotMeta?
    let info: [String: Any]?

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: About.name(info: info))
                            .font(.title2.bold())
                        Text(verbatim: About.version(info: info))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .accessibilityElement(children: .combine)
            }

            Section {
                Text(verbatim: About.riotDisclaimer)
                    .textSelection(.enabled)
            } header: {
                Text("Aviso legal de Riot Games", tableName: "About")
            }

            Section {
                Label {
                    Text(verbatim: About.snapshotLine(meta))
                } icon: {
                    Image(systemName: meta == nil ? "chart.bar.xaxis" : "chart.bar")
                }
                Label {
                    Text(
                        "Las estadísticas vienen del pipeline propio de Mito, sobre la API pública de Riot Games.",
                        tableName: "About")
                } icon: {
                    Image(systemName: "server.rack")
                }
                Label {
                    Text("Tus datos personales quedan en esta Mac.", tableName: "About")
                } icon: {
                    Image(systemName: "lock")
                }
                Label {
                    Text("Mito no tiene telemetría.", tableName: "About")
                } icon: {
                    Image(systemName: "eye.slash")
                }
            } header: {
                Text("Datos y privacidad", tableName: "About")
            }

            Section {
                Text("Código disponible bajo PolyForm Shield 1.0.0", tableName: "About")
                if let repository = About.repository {
                    Link(destination: repository) {
                        Text("Ver el código y la licencia", tableName: "About")
                    }
                }
            } header: {
                Text("Licencia", tableName: "About")
            }

            Section {
                ForEach(About.notices) { notice in
                    NoticeRow(notice: notice)
                }
            } header: {
                Text("Componentes de terceros", tableName: "About")
            }
        }
        .formStyle(.grouped)
    }
}

private struct NoticeRow: View {
    let notice: About.Notice

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: notice.text)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                if let url = notice.url {
                    Link(destination: url) {
                        Text("Ver el proyecto", tableName: "About")
                    }
                }
            }
        } label: {
            Text(verbatim: "\(notice.name) — \(notice.license)")
        }
    }
}

#if DEBUG
    #Preview("Con estadísticas") {
        AboutScreen(meta: .aboutPreview, info: Bundle.main.infoDictionary)
            .frame(width: 520, height: 360)
    }

    #Preview("Sin estadísticas") {
        AboutScreen(meta: nil, info: Bundle.main.infoDictionary)
            .frame(width: 520, height: 360)
    }

    extension SnapshotMeta {
        fileprivate static let aboutPreview = SnapshotMeta(
            patch: Patch(rawValue: "16.21"), queue: QueueID(rawValue: 420),
            bracket: .emeraldPlus, matches: 412_339, blendPatches: [Patch(rawValue: "16.21")],
            thresholds: [:],
            priors: SmoothingPriors(
                championRoleStrength: 100, championRoleBaseline: 0.5, relationStrength: 200,
                loadoutStrength: 500),
            tierCutoffs: [:])
    }
#endif
