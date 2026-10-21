import MitoCore
import SwiftUI

/// The "Build" tab of the analysis panel (§20.2): what the importer would send for your
/// champion, part by part, with the alternatives it passed over. Importing stays with Import.
struct BuildTab: View {
    let subject: AnalysisSubject
    /// Optional so a preview without the app still renders, with the default settings.
    @Environment(AppModel.self) private var app: AppModel?

    var body: some View {
        BuildView(
            content: BuildContent.derive(
                subject, settings: app?.settingsModel.value.importing ?? ImportSettings()),
            names: subject.names)
    }
}

struct BuildView: View {
    let content: BuildContent
    let names: ReasonNames

    var body: some View {
        switch content.state {
        case .noChampion:
            Empty(
                title: Text("Sin campeón todavía", tableName: "Build"),
                description: Text(
                    "Lockeá o elegí un campeón para ver su build.", tableName: "Build"))
        case .aram(nil):
            Empty(
                title: Text("Sin build de ARAM", tableName: "Build"),
                description: Text(
                    "Todavía no hay estadísticas de ARAM. Si guardás una página fija para \(content.champion), aparece acá.",
                    tableName: "Build"))
        case .aram(let page?):
            VStack(alignment: .leading, spacing: 8) {
                Text("Tu página fija de \(content.champion)", tableName: "Build")
                    .font(.headline)
                Text("Sin estadísticas de ARAM: solo tu página guardada.", tableName: "Build")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                OptionRow(option: page, names: names, isChosen: true)
            }
        case .noData:
            Empty(
                title: Text("Sin datos de \(content.champion)", tableName: "Build"),
                description: Text(
                    "El parche no tiene partidas suficientes para armar su build.",
                    tableName: "Build"))
        case .loadout(let parts):
            VStack(alignment: .leading, spacing: 16) {
                Header(content: content)
                ForEach(parts) { part in
                    PartSection(part: part, opponent: content.opponent, names: names)
                }
            }
        }
    }
}

private struct Empty: View {
    let title: Text
    let description: Text

    var body: some View {
        ContentUnavailableView {
            Label {
                title
            } icon: {
                Image(systemName: "hammer")
            }
        } description: {
            description
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }
}

private struct Header: View {
    let content: BuildContent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            title.font(.headline)
            Label {
                framing
            } icon: {
                Image(
                    systemName: content.framing == .ifYouPick
                        ? "questionmark.circle" : "square.and.arrow.down")
            }
            .font(.callout)
            Label {
                adaptation
            } icon: {
                Image(
                    systemName: content.opponent == nil && content.profiles.isEmpty
                        ? "star" : "scope")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var title: Text {
        guard let role = content.role else { return Text(verbatim: content.champion) }
        return Text("\(content.champion) · \(Text(role.shortName))", tableName: "Build")
    }

    private var framing: Text {
        switch content.framing {
        case .imports: Text("Lo que se va a importar", tableName: "Build")
        case .importsOnLock:
            Text("Lo que se importa cuando lockees a \(content.champion)", tableName: "Build")
        case .ifYouPick:
            Text("Si elegís \(content.champion), se importaría esto", tableName: "Build")
        }
    }

    private var adaptation: Text {
        let profiles = content.profiles.map(ReasonText.profileName)
            .formatted(.list(type: .and))
        switch (content.opponent, profiles.isEmpty) {
        case (nil, true):
            return Text("Build general del campeón", tableName: "Build")
        case (nil, false):
            return Text("Adaptado a un equipo con \(profiles)", tableName: "Build")
        case (let opponent?, true):
            return opponent.isInferred
                ? Text("Adaptado a \(opponent.name), tu rival probable", tableName: "Build")
                : Text("Adaptado a \(opponent.name)", tableName: "Build")
        case (let opponent?, false):
            return opponent.isInferred
                ? Text(
                    "Adaptado a \(opponent.name), tu rival probable, y a un equipo con \(profiles)",
                    tableName: "Build")
                : Text(
                    "Adaptado a \(opponent.name) y a un equipo con \(profiles)",
                    tableName: "Build")
        }
    }
}

private struct PartSection: View {
    let part: BuildPart
    let opponent: BuildContent.Opponent?
    let names: ReasonNames

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: part.title).font(.subheadline.weight(.semibold))
                SourceLabel(source: part.source, opponent: opponent)
                if !part.isImported {
                    Label {
                        part.id == .skillOrder
                            ? Text("Solo de referencia", tableName: "Build")
                            : Text("Apagado en Ajustes", tableName: "Build")
                    } icon: {
                        Image(systemName: "nosign")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            ForEach(part.chosen) { option in
                OptionRow(option: option, names: names, isChosen: true)
            }
            if !part.alternatives.isEmpty {
                Text("Alternativas", tableName: "Build")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                ForEach(part.alternatives) { option in
                    OptionRow(option: option, names: names, isChosen: false)
                }
            }
        }
    }
}

private struct SourceLabel: View {
    let source: BuildPart.Source
    let opponent: BuildContent.Opponent?

    var body: some View {
        Label {
            text
        } icon: {
            Image(systemName: symbol)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var text: Text {
        switch source {
        case .general: Text("General", tableName: "Build")
        case .adaptedToOpponent:
            if let opponent {
                opponent.isInferred
                    ? Text("Adaptado a \(opponent.name) (rival probable)", tableName: "Build")
                    : Text("Adaptado a \(opponent.name)", tableName: "Build")
            } else {
                Text("Adaptado al rival", tableName: "Build")
            }
        case .adaptedToProfiles(let profiles):
            Text(
                "Adaptado a \(profiles.map(ReasonText.profileName).formatted(.list(type: .and)))",
                tableName: "Build")
        case .override: Text("Fija del override", tableName: "Build")
        case .generalWithoutFixed: Text("Sin fija guardada: va la general", tableName: "Build")
        case .skippedByOverride: Text("El override no importa ítems", tableName: "Build")
        case .situational: Text("Según el equipo rival", tableName: "Build")
        }
    }

    private var symbol: String {
        switch source {
        case .general: "star"
        case .adaptedToOpponent: "scope"
        case .adaptedToProfiles, .situational: "person.3.sequence"
        case .override, .generalWithoutFixed: "pin"
        case .skippedByOverride: "nosign"
        }
    }
}

/// One VoiceOver element: the option, its sample, and its reasons.
private struct OptionRow: View {
    let option: BuildOption
    let names: ReasonNames
    let isChosen: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: isChosen ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isChosen ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: option.title)
                    .font(isChosen ? .body.weight(.medium) : .callout)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle = option.subtitle {
                    Text(verbatim: subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(option.reasons, id: \.self) { reason in
                    ReasonRow(reason: reason, names: names)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if let level = option.level {
                ConfidenceIndicator(level: level)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }
}

extension Role {
    fileprivate var shortName: LocalizedStringResource {
        switch self {
        case .top: LocalizedStringResource("TOP", table: "Build")
        case .jungle: LocalizedStringResource("JG", table: "Build")
        case .middle: LocalizedStringResource("MID", table: "Build")
        case .bottom: LocalizedStringResource("ADC", table: "Build")
        case .utility: LocalizedStringResource("SUP", table: "Build")
        }
    }
}

// MARK: Previews

#Preview("Adaptado") {
    let reason = { (part: LoadoutPart, usage: Double, winrate: Double, games: Int) in
        [
            Reason(
                kind: .generalChoice(part: part, usage: usage, winrate: winrate, games: games),
                sample: nil)
        ]
    }
    BuildView(
        content: BuildContent(
            champion: "Ahri", role: .middle, framing: .imports,
            opponent: BuildContent.Opponent(name: "Zed", isInferred: true), profiles: [.heavyAD],
            state: .loadout([
                BuildPart(
                    id: .runes, title: "Runas", source: .adaptedToOpponent, isImported: true,
                    chosen: [
                        BuildOption(
                            id: "a", title: "Electrocutar",
                            subtitle: "Dominación + Brujería · Impacto repentino · Globos oculares",
                            level: .usable, reasons: reason(.runes, 0.3, 0.562, 300))
                    ],
                    alternatives: [
                        BuildOption(
                            id: "b", title: "Ímpetu gradual", subtitle: "Brujería + Inspiración",
                            level: .belowMinimum, reasons: reason(.runes, 0.08, 0.51, 80))
                    ]),
                BuildPart(
                    id: .spells, title: "Spells", source: .general, isImported: false,
                    chosen: [
                        BuildOption(
                            id: "c", title: "Destello + Prender", subtitle: nil, level: .reliable,
                            reasons: reason(.spells, 0.9, 0.52, 18_000))
                    ], alternatives: []),
                BuildPart(
                    id: .items(.core), title: "Núcleo", source: .adaptedToProfiles([.heavyAD]),
                    isImported: true,
                    chosen: [
                        BuildOption(
                            id: "d", title: "Luden · Sombrero de Rabadon", subtitle: nil,
                            level: .reliable, reasons: reason(.items(.core), 0.4, 0.53, 4_000))
                    ], alternatives: []),
                BuildPart(
                    id: .skillOrder, title: "Habilidades", source: .general, isImported: false,
                    chosen: [
                        BuildOption(
                            id: "e", title: "Q > W > E", subtitle: "Empieza Q · W · E",
                            level: .reliable, reasons: reason(.skillOrder, 0.7, 0.52, 7_000))
                    ], alternatives: []),
            ])),
        names: .preview
    )
    .padding()
    .frame(width: 700)
}

#Preview("Si elegís, override") {
    BuildView(
        content: BuildContent(
            champion: "Ahri", role: .middle, framing: .ifYouPick, opponent: nil, profiles: [],
            state: .loadout([
                BuildPart(
                    id: .runes, title: "Runas", source: .override, isImported: true,
                    chosen: [
                        BuildOption(
                            id: "a", title: "Cometa arcano", subtitle: "Brujería + Dominación",
                            level: nil, reasons: [])
                    ], alternatives: []),
                BuildPart(
                    id: .skippedItems, title: "Ítems", source: .skippedByOverride,
                    isImported: true, chosen: [], alternatives: []),
            ])),
        names: .preview
    )
    .padding()
    .frame(width: 700)
}

#Preview("ARAM sin página") {
    BuildView(
        content: BuildContent(
            champion: "Ahri", role: nil, framing: .imports, opponent: nil, profiles: [],
            state: .aram(fixedPage: nil)),
        names: .preview
    )
    .frame(width: 700)
}
