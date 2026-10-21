import Charts
import MitoCore
import SwiftUI

/// `DurationCurveChart(curve:)` of §22.3: winrate by game length, one line per champion told
/// apart by color and by symbol, with the summary line under it.
struct DurationCurveChart: View {
    let curve: CurveChartData

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Chart {
                RuleMark(y: .value(Text("Winrate", tableName: "DesignSystem"), 0.5))
                    .foregroundStyle(Color.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .accessibilityHidden(true)
                ForEach(curve.series) { series in
                    ForEach(series.points) { point in
                        LineMark(
                            x: .value(Text("Minutos", tableName: "DesignSystem"), point.label),
                            y: .value(Text("Winrate", tableName: "DesignSystem"), point.winrate)
                        )
                        .foregroundStyle(
                            by: .value(Text("Campeón", tableName: "DesignSystem"), series.name)
                        )
                        .symbol(by: .value(Text("Campeón", tableName: "DesignSystem"), series.name))
                        .interpolationMethod(.monotone)
                        .accessibilityLabel(point.accessibilityLabel)
                        .accessibilityValue(point.accessibilityValue)
                    }
                }
            }
            .chartXScale(domain: curve.axisLabels)
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
                Text("Duración de la partida (minutos)", tableName: "DesignSystem")
            }
            .frame(height: 160)
            .accessibilityLabel(
                Text("Winrate por duración de la partida", tableName: "DesignSystem"))

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let summary = curve.summary {
                    Text(verbatim: summary)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if curve.sample.isLowSample {
                    ConfidenceIndicator(level: curve.sample)
                }
            }
        }
    }
}

struct CurveChartData: Equatable {
    struct Series: Equatable, Identifiable {
        let id: ChampionID
        let name: String
        let points: [Point]
    }

    struct Point: Equatable, Identifiable {
        let id: DurationBucket
        /// "<20", "20–25", "40+".
        let label: String
        let winrate: Double
        /// "Ahri, de 20 a 25 minutos".
        let accessibilityLabel: String
        /// "52,3 %".
        let accessibilityValue: String
    }

    let series: [Series]
    /// The buckets any series has, in game-length order: Charts orders categories as it meets them.
    let axisLabels: [String]
    /// "Ahri escala mejor que Zed desde el minuto 35"; `nil` when nothing stands out.
    let summary: String?
    /// The lowest sample of the curves drawn.
    let sample: SampleLevel
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
    DurationCurveChart(curve: .preview)
        .padding()
        .frame(width: 520)
}
