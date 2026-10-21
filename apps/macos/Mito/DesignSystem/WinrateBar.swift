import MitoCore
import SwiftUI

/// How far `value` sits from `baseline` (§22.3): a bar that grows right of the center line when
/// favorable and left when not, so the side carries the sign and color only follows it. Below
/// "confiable" it goes gray.
struct WinrateBar: View {
    let value: Double
    let baseline: Double
    let confidence: SampleLevel

    /// The winrate points that fill one half of the bar.
    static let span = 0.05

    var body: some View {
        let fraction = Self.fraction(value: value, baseline: baseline)
        HStack(spacing: 1) {
            half(fill: max(-fraction, 0), anchor: .trailing)
            half(fill: max(fraction, 0), anchor: .leading)
        }
        .frame(height: 6)
        .frame(minWidth: 48, idealWidth: 80, maxWidth: 120)
        .animation(.default, value: fraction)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text(
                verbatim: Self.accessibilityText(
                    value: value, baseline: baseline, confidence: confidence)))
    }

    private func half(fill: Double, anchor: UnitPoint) -> some View {
        Rectangle()
            .fill(fillStyle)
            .scaleEffect(x: fill, anchor: anchor)
            .background(.quaternary)
            .clipShape(.capsule)
    }

    private var fillStyle: AnyShapeStyle {
        confidence == .reliable
            ? AnyShapeStyle(WinratePoints.tone(value - baseline).color)
            : AnyShapeStyle(.secondary)
    }

    /// From −1 (a full half to the left) to 1, rounded as the text is so the two agree.
    static func fraction(value: Double, baseline: Double) -> Double {
        let points = WinratePoints.rounded(value - baseline) / 100
        return min(max(points / span, -1), 1)
    }

    /// "+3,8 puntos de winrate, conf. alta".
    static func accessibilityText(
        value: Double, baseline: Double, confidence: SampleLevel, locale: Locale = .current
    ) -> String {
        let points = WinratePoints.text(value - baseline, locale: locale)
        let sample = String(localized: ConfidenceIndicator.title(confidence))
        return String(localized: "\(points) puntos de winrate, \(sample)", table: "DesignSystem")
    }
}

#Preview {
    Grid(alignment: .leading, verticalSpacing: 8) {
        ForEach(
            [
                (0.038, SampleLevel.reliable), (0.012, .reliable), (-0.021, .reliable),
                (0.09, .reliable), (0.025, .usable), (0, .reliable),
            ],
            id: \.0
        ) { value, confidence in
            GridRow {
                DeltaBadge(delta: value)
                WinrateBar(value: value, baseline: 0, confidence: confidence)
                ConfidenceIndicator(level: confidence)
            }
        }
    }
    .padding()
}
