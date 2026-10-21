import Charts
import MitoCore
import SwiftUI

/// Winrate by game length for each curve (§20.2), one line per champion told apart by color and
/// by symbol, with the summary line under it.
struct DurationCurveChart: View {
    let data: CurveChartData

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Chart {
                RuleMark(y: .value(Text("Winrate", tableName: "Matchup"), 0.5))
                    .foregroundStyle(Color.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .accessibilityHidden(true)
                ForEach(data.series) { series in
                    ForEach(series.points) { point in
                        LineMark(
                            x: .value(Text("Minutos", tableName: "Matchup"), point.label),
                            y: .value(Text("Winrate", tableName: "Matchup"), point.winrate)
                        )
                        .foregroundStyle(
                            by: .value(Text("Campeón", tableName: "Matchup"), series.name)
                        )
                        .symbol(by: .value(Text("Campeón", tableName: "Matchup"), series.name))
                        .interpolationMethod(.monotone)
                        .accessibilityLabel(point.accessibilityLabel)
                        .accessibilityValue(point.accessibilityValue)
                    }
                }
            }
            .chartXScale(domain: data.axisLabels)
            .chartYScale(domain: .automatic(includesZero: false))
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let winrate = value.as(Double.self) {
                            Text(winrate, format: .percent.precision(.fractionLength(0)))
                        }
                    }
                }
            }
            .chartXAxisLabel {
                Text("Duración de la partida (minutos)", tableName: "Matchup")
            }
            .frame(height: 160)
            .accessibilityLabel(Text("Winrate por duración de la partida", tableName: "Matchup"))

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let summary = data.summary {
                    Text(verbatim: summary)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if data.sample.isLowSample {
                    ConfidenceIndicator(level: data.sample)
                }
            }
        }
    }
}

extension CurveChartData {
    static let preview = CurveChartData(
        series: [
            Series(
                id: ChampionID(rawValue: 103), name: "Ahri",
                points: zip(
                    DurationBucket.allCases, [0.488, 0.502, 0.515, 0.524, 0.531, 0.537]
                ).map(Self.previewPoint("Ahri"))),
            Series(
                id: ChampionID(rawValue: 238), name: "Zed",
                points: zip(
                    DurationBucket.allCases, [0.534, 0.522, 0.508, 0.496, 0.487, 0.479]
                ).map(Self.previewPoint("Zed"))),
        ],
        axisLabels: DurationBucket.allCases.map(\.rawValue),
        summary: "Ahri escala mejor que Zed desde el minuto 35", sample: .reliable)

    private static func previewPoint(_ name: String) -> ((DurationBucket, Double)) -> Point {
        { pair in
            let (bucket, winrate) = pair
            return Point(
                id: bucket, label: bucket.rawValue, winrate: winrate,
                accessibilityLabel: "\(name), \(bucket.rawValue)",
                accessibilityValue: winrate.formatted(.percent))
        }
    }
}

#Preview {
    DurationCurveChart(data: .preview)
        .padding()
        .frame(width: 520)
}
