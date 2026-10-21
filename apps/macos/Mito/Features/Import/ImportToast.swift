import LCUKit
import MitoCore
import MitoEngine
import MitoImport
import SwiftUI

extension View {
    /// Hosts the import toast at the top of the main window and tells `ImportModel` the window
    /// is open, so imports land here instead of as notifications.
    func importToast() -> some View {
        modifier(ImportToastHost())
    }
}

struct ImportToastHost: ViewModifier {
    @Environment(AppModel.self) private var app

    func body(content: Content) -> some View {
        let model = app.importing
        content
            .overlay(alignment: .top) {
                if let outcome = model.outcome {
                    ImportToast(
                        outcome: outcome,
                        confirm: { Task { await model.confirmReplacement() } },
                        decline: { model.declineReplacement() },
                        dismiss: { model.dismiss(outcome.id) }
                    )
                    .id(outcome.id)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: outcome.id) {
                        AccessibilityNotification.Announcement(String(localized: outcome.headline))
                            .post()
                        try? await Task.sleep(for: ImportToast.lifetime)
                        if !Task.isCancelled { model.dismiss(outcome.id) }
                    }
                }
            }
            .animation(.snappy, value: model.outcome?.id)
            .onAppear { model.windowAppeared() }
            .onDisappear { model.windowDisappeared() }
    }
}

struct ImportToast: View {
    static let lifetime: Duration = .seconds(6)

    let outcome: ImportOutcome
    let confirm: () -> Void
    let decline: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(outcome.headline)
                    .font(.headline)
                Spacer(minLength: 12)
                if !outcome.needsConfirmation {
                    Button(action: dismiss) {
                        Label {
                            Text("Cerrar", tableName: "Import")
                        } icon: {
                            Image(systemName: "xmark")
                        }
                        .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.cancelAction)
                }
            }
            ForEach(outcome.rows) { row in
                ImportToastRow(row: row)
            }
            if outcome.needsConfirmation {
                HStack {
                    Spacer()
                    Button(action: decline) {
                        Text("Ahora no", tableName: "Import")
                    }
                    Button(action: confirm) {
                        Text("Reemplazar", tableName: "Import")
                    }
                    .keyboardShortcut(.defaultAction)
                }
                .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 340, alignment: .leading)
        .floatingSurface(in: .rect(cornerRadius: 14))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        .accessibilityElement(children: .contain)
    }
}

struct ImportToastRow: View {
    let row: ImportOutcome.Row

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: row.symbol)
                .foregroundStyle(row.tone.color)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(row.part.title)
                .fontWeight(.medium)
            Text(row.status)
                .foregroundStyle(.secondary)
            if row.isLowSample {
                Text("· muestra baja", tableName: "Import")
                    .foregroundStyle(.tertiary)
            }
            if let origin = row.origin {
                Text(origin.marker)
                    .foregroundStyle(.tertiary)
            }
            if let marker = row.adaptationMarker {
                Text(verbatim: marker)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .help(marker)
            }
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
    }
}

extension ImportOutcome.Tone {
    /// Always next to its symbol, never alone.
    var color: Color {
        switch self {
        case .done: .green
        case .neutral: .secondary
        case .attention: .orange
        case .failure: .red
        }
    }
}

extension View {
    /// Liquid Glass on macOS 26, a material in the same shape before it.
    @ViewBuilder
    fileprivate func floatingSurface(in shape: some Shape) -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
        }
    }
}

// MARK: Previews

extension ImportOutcome {
    fileprivate static func preview(
        runes: StepResult = .applied, spells: StepResult = .applied, items: StepResult = .applied,
        itemsUnavailable: ItemsUnavailable? = nil, lowSample: Set<Part> = [],
        origins: [Part: Origin] = [:], adaptations: [Part: [Adaptation]] = [:],
        missing: Missing? = nil
    ) -> ImportOutcome {
        ImportOutcome(
            id: 1, champion: ChampionID(rawValue: 103), title: "Ahri MID",
            report: ImportReport(runes: runes, spells: spells, items: items),
            itemsUnavailable: itemsUnavailable, lowSample: lowSample, origins: origins,
            adaptations: adaptations, missing: missing)
    }
}

private struct ToastPreview: View {
    let outcome: ImportOutcome

    var body: some View {
        ImportToast(outcome: outcome, confirm: {}, decline: {}, dismiss: {})
            .padding(24)
    }
}

#Preview("Importado") {
    ToastPreview(outcome: .preview())
}

#Preview("Muestra baja") {
    ToastPreview(outcome: .preview(lowSample: [.runes, .items]))
}

#Preview("Adaptado") {
    ToastPreview(
        outcome: .preview(
            lowSample: [.items],
            adaptations: [
                .runes: [.opponent("Zed")], .spells: [.opponent("Zed")],
                .items: [
                    .opponent("Zed"),
                    .countersFlag(item: "Morellonomicon", flag: .highHeal, enemies: 2),
                    .situational(item: "Thornmail", profile: .heavyAD),
                ],
            ]))
}

#Preview("Adaptado al perfil") {
    ToastPreview(
        outcome: .preview(
            adaptations: [.runes: [.profile(.heavyAD)], .items: [.profile(.heavyAD)]]))
}

#Preview("Sin estadísticas") {
    ToastPreview(
        outcome: .preview(
            runes: .skipped(.notInLoadout), spells: .skipped(.notInLoadout),
            items: .skipped(.notInLoadout), missing: .stats))
}

#Preview("Con partes omitidas") {
    ToastPreview(
        outcome: .preview(
            runes: .skipped(.noEditablePage), spells: .skipped(.alreadySelected),
            items: .skipped(.disabled)))
}

#Preview("Otro mapa") {
    ToastPreview(
        outcome: .preview(items: .skipped(.notInLoadout), itemsUnavailable: .unsupportedMap))
}

#Preview("Con overrides") {
    ToastPreview(
        outcome: .preview(
            runes: .failed(.invalidRunePage(.unknownStyle(PerkStyleID(rawValue: 8400)))),
            items: .skipped(.notInLoadout), itemsUnavailable: .skippedByOverride,
            origins: [.runes: .override, .spells: .noFixedChoice, .items: .override]))
}

#Preview("Confirmar runas") {
    ToastPreview(outcome: .preview(runes: .needsConfirmation(pageID: 201, pageName: "My page")))
}

#Preview("Con errores") {
    ToastPreview(
        outcome: .preview(
            runes: .failed(.invalidRunePage(.sameStyleTwice)),
            items: .failed(.lcu(.http(status: 500, body: Data())))))
}
