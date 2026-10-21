import Foundation
import MitoCore
import Testing

@testable import Mito

/// Winrate points carry their own sign and an arrow, so color is never alone (§22.1, §22.3).
struct DeltaBadgeTests {
    nonisolated static let locale = Locale(identifier: "es_AR")

    @Test(arguments: [
        (0.038, "+3,8", Tone.favorable, "arrow.up"),
        (-0.034, "\u{2212}3,4", .unfavorable, "arrow.down"),
        (0.12345, "+12,3", .favorable, "arrow.up"),
        (0.0, "0,0", .neutral, "equal"),
        // Rounds to zero: no sign, no color.
        (-0.0004, "0,0", .neutral, "equal"),
        (0.00051, "+0,1", .favorable, "arrow.up"),
    ])
    func formatsTheDeltaAsSignedPoints(delta: Double, text: String, tone: Tone, symbol: String) {
        #expect(WinratePoints.text(delta, locale: Self.locale) == text)
        #expect(WinratePoints.tone(delta) == tone)
        #expect(DeltaBadge.symbol(tone) == symbol)
    }

    @Test func confidenceNamesEveryLevel() {
        #expect(String(localized: ConfidenceIndicator.title(.reliable)) == "conf. alta")
        #expect(String(localized: ConfidenceIndicator.title(.usable)) == "muestra baja")
        #expect(String(localized: ConfidenceIndicator.title(.belowMinimum)) == "sin muestra")
        #expect(
            Set([SampleLevel.reliable, .usable, .belowMinimum].map(ConfidenceIndicator.symbol))
                .count == 3)
    }
}
