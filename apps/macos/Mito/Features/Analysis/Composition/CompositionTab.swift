import MitoCore
import MitoEngine
import SwiftUI

/// The "Composición" tab of the analysis panel (§20.2): both teams side by side.
struct CompositionTab: View {
    let summary: CompositionSummary

    init(subject: AnalysisSubject) {
        summary = CompositionSummary(subject: subject)
    }

    var body: some View {
        if summary.hasData {
            VStack(alignment: .leading, spacing: 14) {
                Notes(summary: summary)
                TeamsGrid(summary: summary)
                if !summary.enemyProfile.isEmpty {
                    Label {
                        Text(verbatim: CompositionText.enemyProfile(summary.enemyProfile))
                    } icon: {
                        Image(systemName: "person.3.sequence")
                    }
                    .font(.callout)
                }
                if !summary.winConditions.isEmpty {
                    WinConditions(conditions: summary.winConditions)
                }
            }
        } else {
            ContentUnavailableView {
                Label {
                    Text("Sin datos de composición", tableName: "Composition")
                } icon: {
                    Image(systemName: "person.3")
                }
            } description: {
                if summary.hasNoMembers {
                    Text("Aparece cuando se lockean campeones.", tableName: "Composition")
                } else {
                    Text(
                        "Los campeones lockeados no tienen perfil en este parche.",
                        tableName: "Composition")
                }
            }
            .frame(maxWidth: .infinity, minHeight: 180)
        }
    }
}

/// What the read assumes: your unlocked pick and the enemy roles that are only inferred.
private struct Notes: View {
    let summary: CompositionSummary

    var body: some View {
        if summary.assumedPick != nil || summary.hasInferredEnemyRoles {
            VStack(alignment: .leading, spacing: 4) {
                if let pick = summary.assumedPick {
                    Label {
                        Text(verbatim: CompositionText.assumedPick(pick))
                    } icon: {
                        Image(systemName: "hand.point.up.left")
                    }
                }
                if summary.hasInferredEnemyRoles {
                    Label {
                        Text(
                            "Roles del rival inferidos: su lectura es estimada.",
                            tableName: "Composition")
                    } icon: {
                        Image(systemName: "questionmark.circle")
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

private struct TeamsGrid: View {
    let summary: CompositionSummary

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 20, verticalSpacing: 10) {
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                TeamHeader(team: summary.allies, side: .allies)
                TeamHeader(team: summary.enemies, side: .enemies)
            }
            GridRow {
                RowTitle(metric: .damage)
                DamageCell(team: summary.allies, side: .allies)
                DamageCell(team: summary.enemies, side: .enemies)
            }
            GridRow {
                RowTitle(metric: .frontline)
                LevelCell(level: summary.allies.read.frontline, metric: .frontline, side: .allies)
                LevelCell(level: summary.enemies.read.frontline, metric: .frontline, side: .enemies)
            }
            GridRow {
                RowTitle(metric: .crowdControl)
                LevelCell(
                    level: summary.allies.read.crowdControl, metric: .crowdControl, side: .allies)
                LevelCell(
                    level: summary.enemies.read.crowdControl, metric: .crowdControl,
                    side: .enemies)
            }
            if summary.showsTiming {
                GridRow {
                    RowTitle(metric: .curve)
                    ValueCell(
                        text: CompositionText.curve(summary.allies.read.curve), metric: .curve,
                        side: .allies)
                    ValueCell(
                        text: CompositionText.curve(summary.enemies.read.curve), metric: .curve,
                        side: .enemies)
                }
                GridRow {
                    RowTitle(metric: .spikes)
                    ValueCell(
                        text: CompositionText.spikes(summary.allies.read.spikes),
                        metric: .spikes, side: .allies)
                    ValueCell(
                        text: CompositionText.spikes(summary.enemies.read.spikes),
                        metric: .spikes, side: .enemies)
                }
            }
        }
        .font(.callout)
    }
}

private enum Metric {
    case damage
    case frontline
    case crowdControl
    case curve
    case spikes

    var title: LocalizedStringResource {
        switch self {
        case .damage: LocalizedStringResource("Daño", table: "Composition")
        case .frontline: LocalizedStringResource("Frontline", table: "Composition")
        case .crowdControl: LocalizedStringResource("CC", table: "Composition")
        case .curve: LocalizedStringResource("Curva", table: "Composition")
        case .spikes: LocalizedStringResource("Power spikes", table: "Composition")
        }
    }
}

extension TeamSide {
    fileprivate var title: LocalizedStringResource {
        switch self {
        case .allies: LocalizedStringResource("Tu equipo", table: "Composition")
        case .enemies: LocalizedStringResource("Rival", table: "Composition")
        }
    }
}

private struct RowTitle: View {
    let metric: Metric

    var body: some View {
        Text(metric.title)
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.trailing)
            .accessibilityHidden(true)
    }
}

private struct TeamHeader: View {
    let team: CompositionSummary.Team
    let side: TeamSide

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(side.title).font(.headline)
            if !team.members.isEmpty {
                HStack(spacing: 4) {
                    ForEach(Array(team.members.enumerated()), id: \.offset) { _, member in
                        ChampionIcon(id: member.champion, size: 22, label: member.name)
                    }
                }
            }
            if team.isPartial {
                Label {
                    Text(verbatim: CompositionText.coverage(team))
                } icon: {
                    Image(systemName: "exclamationmark.circle")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .help(Text("Lectura parcial: no todos tienen datos", tableName: "Composition"))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// One VoiceOver element per cell: the metric and the team, then the value.
private struct ValueCell: View {
    let text: String
    let metric: Metric
    let side: TeamSide

    var body: some View {
        Text(verbatim: text)
            .fixedSize(horizontal: false, vertical: true)
            .modifier(CellAccessibility(metric: metric, side: side, value: text))
    }
}

private struct LevelCell: View {
    let level: CompositionLevel?
    let metric: Metric
    let side: TeamSide

    var body: some View {
        let text = level.map(CompositionText.level) ?? Self.noData
        Label {
            Text(verbatim: text)
        } icon: {
            Image(systemName: "cellularbars", variableValue: Self.fill(level))
        }
        .labelStyle(.titleAndIcon)
        .modifier(CellAccessibility(metric: metric, side: side, value: text))
    }

    static var noData: String { String(localized: "Sin datos", table: "Composition") }

    private static func fill(_ level: CompositionLevel?) -> Double {
        switch level {
        case .low: 0.34
        case .medium: 0.67
        case .high: 1
        case nil: 0
        }
    }
}

/// Physical and magic shares as one bar, true damage in the rest; the text carries the numbers.
private struct DamageCell: View {
    let team: CompositionSummary.Team
    let side: TeamSide

    var body: some View {
        let profile = team.read.profile
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: team.hasData ? CompositionText.damage(profile) : LevelCell.noData)
                .monospacedDigit()
            if team.hasData {
                DamageBar(physical: profile.physicalShare, magic: profile.magicShare)
            }
        }
        .modifier(
            CellAccessibility(
                metric: .damage, side: side,
                value: team.hasData
                    ? CompositionText.damageAccessibility(profile) : LevelCell.noData))
    }
}

private struct DamageBar: View {
    let physical: Double
    let magic: Double

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                Rectangle().fill(.orange).frame(width: proxy.size.width * physical)
                Rectangle().fill(.blue).frame(width: proxy.size.width * magic)
                Rectangle().fill(.quaternary)
            }
            .clipShape(.capsule)
        }
        .frame(minWidth: 80, idealWidth: 140, maxWidth: 180)
        .frame(height: 6)
        .animation(.default, value: physical)
    }
}

private struct CellAccessibility: ViewModifier {
    let metric: Metric
    let side: TeamSide
    let value: String

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                Text(
                    "\(String(localized: metric.title)), \(String(localized: side.title))",
                    tableName: "Composition")
            )
            .accessibilityValue(Text(verbatim: value))
    }
}

private struct WinConditions: View {
    let conditions: [WinCondition]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Condiciones de victoria", tableName: "Composition").font(.headline)
            ForEach(conditions, id: \.self) { condition in
                Label {
                    Text(verbatim: CompositionText.winCondition(condition))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "flag.checkered")
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            }
        }
    }
}

// MARK: Previews

#Preview("Bans y picks") {
    let model = AnalysisModel(
        champSelect: PreviewDraft.model(PreviewDraft.banPick, queue: .rankedSolo),
        stats: { CompositionPreviewStats() })
    model.tab = .composition
    return AnalysisPanel(model: model)
        .padding()
        .frame(width: 900, height: 420)
}

#Preview("Sin datos") {
    let model = AnalysisModel(
        champSelect: PreviewDraft.model(PreviewDraft.planning, queue: .rankedSolo),
        stats: { CompositionPreviewStats(profiles: false) })
    model.tab = .composition
    return AnalysisPanel(model: model)
        .padding()
        .frame(width: 900, height: 320)
}

/// Every champion in every role, with a spread of profiles and curves.
private struct CompositionPreviewStats: StatsProvider {
    var profiles = true

    var meta: SnapshotMeta? {
        SnapshotMeta(
            patch: Patch(rawValue: "16.21"), queue: QueueID(rawValue: 420),
            bracket: .emeraldPlus, matches: 400_000, blendPatches: [Patch(rawValue: "16.21")],
            thresholds: [:],
            priors: SmoothingPriors(
                championRoleStrength: 100, championRoleBaseline: 0.5, relationStrength: 200,
                loadoutStrength: 500),
            tierCutoffs: [:],
            profileRules: ProfileRules(
                minimumChampions: 1, heavyADPhysicalShare: 0.65, heavyAPMagicShare: 0.6,
                heavyCCScore: 0.6, mixedExcludes: [.heavyAD, .heavyAP]))
    }

    func roleGames(for champion: ChampionID) -> [Role: Int] {
        [.middle: champion.rawValue == 238 ? 3000 : 10]
    }

    func championProfile(for champion: ChampionID, role: Role) -> ChampionProfile? {
        guard profiles else { return nil }
        let seed = Double(champion.rawValue % 7) / 7
        return ChampionProfile(
            physicalShare: 0.9 - seed * 0.6, magicShare: seed * 0.6, trueShare: 0.1,
            damagePerMinute: 600 + seed * 300, tankiness: champion.rawValue == 266 ? 0.8 : seed,
            ccScore: 1 - seed, timelineGames: 500, levelSixSeconds: 420 + Int(seed * 60),
            firstItemSeconds: 560 + Int(seed * 120), secondItemSeconds: 960,
            thirdItemSeconds: 1380)
    }

    func durationCurves(for champion: ChampionID, role: Role) -> [DurationBucket: RelationStats] {
        guard profiles else { return [:] }
        let early = champion.rawValue == 238 ? 40 : 60
        return [
            .under20: RelationStats(games: 100, wins: early),
            .from25To30: RelationStats(games: 100, wins: 50),
            .over40: RelationStats(games: 100, wins: 100 - early),
        ]
    }
}
