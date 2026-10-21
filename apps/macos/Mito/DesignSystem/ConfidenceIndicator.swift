import MitoCore
import SwiftUI

/// The sample level behind a recommendation (§18.2): an icon and its words, never color alone.
struct ConfidenceIndicator: View {
    let level: SampleLevel

    var body: some View {
        Label {
            Text(Self.title(level))
        } icon: {
            Image(systemName: Self.symbol(level))
        }
        .labelStyle(.titleAndIcon)
        .font(.caption)
        .foregroundStyle(
            level == .reliable ? AnyShapeStyle(Color.favorable) : AnyShapeStyle(.secondary))
    }

    static func title(_ level: SampleLevel) -> LocalizedStringResource {
        switch level {
        case .reliable: LocalizedStringResource("conf. alta", table: "DesignSystem")
        case .usable: LocalizedStringResource("muestra baja", table: "DesignSystem")
        case .belowMinimum: LocalizedStringResource("sin muestra", table: "DesignSystem")
        }
    }

    static func symbol(_ level: SampleLevel) -> String {
        switch level {
        case .reliable: "checkmark.seal.fill"
        case .usable: "exclamationmark.circle"
        case .belowMinimum: "questionmark.circle"
        }
    }
}

#Preview {
    VStack(alignment: .leading) {
        ConfidenceIndicator(level: .reliable)
        ConfidenceIndicator(level: .usable)
        ConfidenceIndicator(level: .belowMinimum)
    }
    .padding()
}
