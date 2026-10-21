import Foundation
import Testing

@testable import Mito

/// One rounding feeds the text and the tone, so a number never reads "+0" or wears a color its
/// text does not show (§22.1).
struct SignedNumberTests {
    nonisolated static let locale = Locale(identifier: "es_AR")

    @Test(arguments: [
        (2.5, 0, "+2", Tone.favorable),
        (3.5, 0, "+4", .favorable),
        (-2.5, 0, "\u{2212}2", .unfavorable),
        (-85.0, 0, "\u{2212}85", .unfavorable),
        (0.5, 0, "0", .neutral),
        (-0.5, 0, "0", .neutral),
        (0.25, 1, "+0,2", .favorable),
        (-0.04, 1, "0,0", .neutral),
        (4.2, 1, "+4,2", .favorable),
        (1234.0, 0, "+1.234", .favorable),
    ])
    func roundsHalfToEvenOnceForTextAndTone(
        value: Double, fractionDigits: Int, text: String, tone: Tone
    ) {
        #expect(
            SignedNumber.text(value, fractionDigits: fractionDigits, locale: Self.locale) == text)
        #expect(SignedNumber.tone(value, fractionDigits: fractionDigits) == tone)
    }

    @Test(arguments: [0.038, -0.034, 0.12345, 0.0, -0.0004, 0.00051, 0.0025, -0.0025])
    func winratePointsAreTheSignedNumberInPoints(delta: Double) {
        #expect(
            WinratePoints.text(delta, locale: Self.locale)
                == SignedNumber.text(delta * 100, fractionDigits: 1, locale: Self.locale))
        #expect(WinratePoints.tone(delta) == SignedNumber.tone(delta * 100, fractionDigits: 1))
    }
}
