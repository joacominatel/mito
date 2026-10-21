import Foundation
import MitoCore
import Testing

@testable import Mito

/// The bar's side follows the sign and VoiceOver reads the value, so color is never alone
/// (§22.1, §22.3).
struct WinrateBarTests {
    nonisolated static let locale = Locale(identifier: "es_AR")

    @Test(arguments: [
        (0.538, 0.5, 0.76),
        (0.479, 0.5, -0.42),
        (0.025, 0.0, 0.5),
        // Past the span the bar is full.
        (0.62, 0.5, 1.0),
        (-0.09, 0.0, -1.0),
        // Rounds to 0,0 like the text: no bar.
        (0.5004, 0.5, 0.0),
    ])
    func theLengthFollowsTheDistanceFromTheBaseline(
        value: Double, baseline: Double, fraction: Double
    ) {
        #expect(abs(WinrateBar.fraction(value: value, baseline: baseline) - fraction) < 1e-9)
    }

    @Test(arguments: [
        (0.038, SampleLevel.reliable, "+3,8 puntos de winrate, conf. alta"),
        (-0.021, .usable, "\u{2212}2,1 puntos de winrate, muestra baja"),
        (0.0, .belowMinimum, "0,0 puntos de winrate, sin muestra"),
    ])
    func voiceOverReadsTheValueAndItsSample(
        value: Double, confidence: SampleLevel, label: String
    ) {
        #expect(
            WinrateBar.accessibilityText(
                value: value, baseline: 0, confidence: confidence, locale: Self.locale) == label)
    }
}
