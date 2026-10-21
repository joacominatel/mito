import SwiftUI

/// "+2,1" / "−3,4" winrate points with an arrow, colored by sign (§22.3).
struct DeltaBadge: View {
    let delta: Double

    var body: some View {
        let tone = WinratePoints.tone(delta)
        Label {
            Text(verbatim: WinratePoints.text(delta))
                .monospacedDigit()
                .contentTransition(.numericText(value: delta))
        } icon: {
            Image(systemName: Self.symbol(tone))
        }
        .labelStyle(.titleAndIcon)
        .font(.callout.weight(.semibold))
        .foregroundStyle(tone.color)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text("\(WinratePoints.text(delta)) puntos de winrate", tableName: "DesignSystem"))
    }

    static func symbol(_ tone: Tone) -> String {
        switch tone {
        case .favorable: "arrow.up"
        case .unfavorable: "arrow.down"
        case .neutral: "equal"
        }
    }
}

#Preview {
    VStack(alignment: .leading) {
        DeltaBadge(delta: 0.038)
        DeltaBadge(delta: -0.034)
        DeltaBadge(delta: 0.0004)
    }
    .padding()
}
