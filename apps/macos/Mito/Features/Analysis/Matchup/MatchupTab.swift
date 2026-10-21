import MitoCore
import SwiftUI

/// The "Matchup" tab of the analysis panel (§20.2): your champion against the lane opponent.
struct MatchupTab: View {
    let subject: AnalysisSubject

    var body: some View {
        switch MatchupPresentation(subject: subject) {
        case .aram:
            EmptyState(
                title: Text("Sin datos de matchup en ARAM", tableName: "Matchup"),
                symbol: "dice")
        case .noChampion:
            EmptyState(
                title: Text("Todavía no hay campeón", tableName: "Matchup"),
                symbol: "person.crop.circle.badge.questionmark",
                description: Text(
                    "El matchup aparece cuando lockeás, hacés hover o hay una recomendación.",
                    tableName: "Matchup"))
        case .noStats:
            EmptyState(
                title: Text("Sin estadísticas todavía", tableName: "Matchup"),
                symbol: "chart.bar.xaxis")
        case .ready(let report):
            MatchupReportView(report: report)
        }
    }
}

private struct EmptyState: View {
    let title: Text
    let symbol: String
    var description: Text?

    var body: some View {
        ContentUnavailableView {
            Label {
                title
            } icon: {
                Image(systemName: symbol)
            }
        } description: {
            description
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }
}

private struct MatchupReportView: View {
    let report: MatchupReport

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                ChampionIcon(id: report.champion, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: report.title)
                        .font(.title3.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Label {
                        Text(verbatim: report.opponent)
                    } icon: {
                        if let rival = report.opponentChampion {
                            ChampionIcon(id: rival, size: 16)
                        } else {
                            Image(systemName: "questionmark.circle")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)

            HStack(alignment: .top, spacing: 24) {
                ForEach(report.winrates) { WinrateBlockView(block: $0) }
                if let diffs = report.laneDiffs {
                    LaneDiffsView(block: diffs)
                }
            }

            if let curve = report.curve {
                MatchupSection(title: Text("Curva por duración", tableName: "Matchup")) {
                    DurationCurveChart(data: curve)
                }
            }

            if !report.spikes.isEmpty {
                MatchupSection(title: Text("Power spikes", tableName: "Matchup")) {
                    ForEach(report.spikes) { LineRow(line: $0) }
                }
            }

            if !report.claves.isEmpty {
                MatchupSection(title: Text("Claves", tableName: "Matchup")) {
                    ForEach(report.claves) { LineRow(line: $0) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MatchupSection<Content: View>: View {
    let title: Text
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            title
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            content
        }
    }
}

/// One stat block, read by VoiceOver as one element.
private struct WinrateBlockView: View {
    let block: WinrateBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: block.title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let value = block.value {
                Text(verbatim: value)
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
            }
            if let interval = block.interval {
                Text(verbatim: interval)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if let delta = block.delta, let caption = block.deltaCaption {
                HStack(spacing: 4) {
                    DeltaBadge(delta: delta)
                    Text(verbatim: caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let note = block.note {
                Text(verbatim: note)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                if let games = block.games {
                    Text(verbatim: games)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let sample = block.sample {
                    ConfidenceIndicator(level: sample)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct LaneDiffsView: View {
    let block: LaneDiffsBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("En la línea", tableName: "Matchup")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ForEach(block.items) { item in
                HStack(spacing: 6) {
                    Text(verbatim: item.id)
                    Label {
                        Text(verbatim: item.value)
                            .monospacedDigit()
                    } icon: {
                        Image(systemName: Self.symbol(item.tone))
                    }
                    .labelStyle(.titleAndIcon)
                    .fontWeight(.semibold)
                    .foregroundStyle(item.tone.color)
                }
                .font(.callout)
            }
            HStack(spacing: 8) {
                Text(verbatim: block.games)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ConfidenceIndicator(level: block.sample)
            }
        }
        .accessibilityElement(children: .combine)
    }

    static func symbol(_ tone: Tone) -> String {
        switch tone {
        case .favorable: "arrow.up"
        case .unfavorable: "arrow.down"
        case .neutral: "equal"
        }
    }
}

/// A spike or clave: its symbol in its tone, the line, and the low-sample mark when it applies.
private struct LineRow: View {
    let line: MatchupReport.Line

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: line.symbol)
                .foregroundStyle(line.tone.color)
                .frame(minWidth: 16)
                .accessibilityHidden(true)
            Text(verbatim: line.text)
                .fixedSize(horizontal: false, vertical: true)
            if let note = line.note {
                Text(verbatim: note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let sample = line.sample, sample.isLowSample {
                ConfidenceIndicator(level: sample)
            }
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
    }
}

// MARK: Previews

#Preview("Contra Zed") {
    MatchupReportView(report: .preview)
        .padding()
        .frame(width: 720)
}

#Preview("Recomendado, sin rival") {
    MatchupReportView(report: .previewWithoutOpponent)
        .padding()
        .frame(width: 720)
}

#Preview("Estados") {
    VStack {
        EmptyState(
            title: Text("Todavía no hay campeón", tableName: "Matchup"),
            symbol: "person.crop.circle.badge.questionmark")
        EmptyState(
            title: Text("Sin datos de matchup en ARAM", tableName: "Matchup"), symbol: "dice")
    }
    .frame(width: 720)
}

extension MatchupReport {
    fileprivate static let preview = MatchupReport(
        title: "Ahri vs Zed", opponent: "Rival de línea: Zed (MID? 82 %)",
        champion: ChampionID(rawValue: 103), opponentChampion: ChampionID(rawValue: 238),
        winrates: [
            WinrateBlock(
                id: .matchup, title: "Winrate contra Zed", value: "52,3 %",
                interval: "IC 90 %: 51,4 % – 53,2 %", delta: 0.021,
                deltaCaption: "respecto del promedio de Ahri", games: "8.212 partidas",
                sample: .reliable, note: nil)
        ],
        laneDiffs: LaneDiffsBlock(
            items: [
                .init(id: "Oro @15", value: "\u{2212}85", tone: .unfavorable),
                .init(id: "CS @15", value: "+4,2", tone: .favorable),
            ], games: "1.204 partidas con timeline", sample: .reliable),
        curve: .preview,
        spikes: [
            Line(
                id: 0, symbol: "bolt", tone: .unfavorable,
                text: "Zed llega a 6 a los 7:10, vos a los 7:40", note: nil, sample: .reliable),
            Line(
                id: 1, symbol: "bolt", tone: .neutral,
                text: "Zed completa el 1.er legendario a los 10:05, vos a los 10:12", note: nil,
                sample: .usable),
        ],
        claves: [
            Line(
                id: 0, symbol: "lightbulb", tone: .neutral,
                text: "Guardá la E para cuando entra la R de Zed.", note: "revisado en 16.20",
                sample: nil),
            Line(
                id: 1, symbol: "chart.line.uptrend.xyaxis", tone: .favorable,
                text: "Escalás mejor que Zed desde el minuto 35: no hace falta forzar temprano",
                note: nil, sample: .reliable),
        ])

    fileprivate static let previewWithoutOpponent = MatchupReport(
        title: "Si elegís Ahri", opponent: "Rival de línea desconocido",
        champion: ChampionID(rawValue: 103), opponentChampion: nil,
        winrates: [
            WinrateBlock(
                id: .general, title: "Winrate general en MID", value: "51,9 %",
                interval: "IC 90 %: 50,4 % – 53,5 %", delta: nil, deltaCaption: nil,
                games: "3.000 partidas", sample: .reliable, note: nil)
        ],
        laneDiffs: nil,
        curve: CurveChartData(
            series: [CurveChartData.preview.series[0]],
            axisLabels: CurveChartData.preview.axisLabels,
            summary: "Ahri rinde más en partidas de 35 minutos o más", sample: .usable),
        spikes: [
            Line(
                id: 0, symbol: "bolt", tone: .neutral, text: "Ahri llega a 6 a los 7:40",
                note: nil, sample: .reliable)
        ],
        claves: [])
}
