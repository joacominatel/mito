import AppKit
import Foundation
import SwiftUI

/// The direction a number points. Color always comes with its sign or icon (§22.1).
nonisolated enum Tone: Hashable {
    case favorable
    case unfavorable
    case neutral

    var color: Color {
        switch self {
        case .favorable: .favorable
        case .unfavorable: .unfavorable
        case .neutral: .secondary
        }
    }
}

extension Color {
    nonisolated static let favorable = Color(nsColor: .favorable)
    nonisolated static let unfavorable = Color(nsColor: .unfavorable)
    nonisolated static let caution = Color(nsColor: .caution)
    nonisolated static let mintReadable = Color(nsColor: .mintReadable)
}

extension NSColor {
    /// The system green, red, orange and mint, darker in light appearances so text and symbols
    /// keep at least 4.5:1 on a light background. Dark appearances keep the system color.
    nonisolated static let favorable = readable(.systemGreen, darkenedBy: 0.4)
    nonisolated static let unfavorable = readable(.systemRed, darkenedBy: 0.25)
    nonisolated static let caution = readable(.systemOrange, darkenedBy: 0.4)
    nonisolated static let mintReadable = readable(.systemMint, darkenedBy: 0.45)

    // AppKit resolves dynamic colors on whatever thread draws.
    nonisolated private static func readable(_ base: NSColor, darkenedBy fraction: CGFloat)
        -> NSColor
    {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? base : base.blended(withFraction: fraction, of: .black) ?? base
        }
    }
}

/// A signed number as the UI shows it: "+4,2", "−85". Zero after rounding has no sign. The
/// minus is U+2212.
enum SignedNumber {
    /// Rounded once, half to even like the formatter, so the text and the tone read one number.
    static func rounded(_ value: Double, fractionDigits: Int) -> Double {
        let scale = pow(10, Double(fractionDigits))
        return (value * scale).rounded(.toNearestOrEven) / scale
    }

    static func text(_ value: Double, fractionDigits: Int, locale: Locale = .current) -> String {
        let shown = rounded(value, fractionDigits: fractionDigits)
        let magnitude = abs(shown).formatted(
            .number.precision(.fractionLength(fractionDigits)).locale(locale))
        if shown > 0 { return "+" + magnitude }
        if shown < 0 { return "\u{2212}" + magnitude }
        return magnitude
    }

    /// A signed share of one: `0.021` is "+2,1 %". Zero after rounding has no sign.
    static func percentText(_ fraction: Double, fractionDigits: Int, locale: Locale = .current)
        -> String
    {
        let shown = rounded(fraction * 100, fractionDigits: fractionDigits)
        let magnitude = (abs(shown) / 100).formatted(
            .percent.precision(.fractionLength(fractionDigits)).locale(locale))
        if shown > 0 { return "+" + magnitude }
        if shown < 0 { return "\u{2212}" + magnitude }
        return magnitude
    }

    static func tone(_ value: Double, fractionDigits: Int) -> Tone {
        let shown = rounded(value, fractionDigits: fractionDigits)
        return shown > 0 ? .favorable : shown < 0 ? .unfavorable : .neutral
    }
}

/// Fractions as the UI reads them (§18.3): `0.021` is "+2,1" winrate points.
enum WinratePoints {
    /// To the one decimal the UI shows, so the sign and the text never disagree.
    static func rounded(_ delta: Double) -> Double {
        SignedNumber.rounded(delta * 100, fractionDigits: 1)
    }

    static func text(_ delta: Double, locale: Locale = .current) -> String {
        SignedNumber.text(delta * 100, fractionDigits: 1, locale: locale)
    }

    static func tone(_ delta: Double) -> Tone {
        SignedNumber.tone(delta * 100, fractionDigits: 1)
    }
}

extension Double {
    /// A share as a whole percentage ("78 %" in es-AR).
    func percentText(locale: Locale = .current) -> String {
        formatted(.percent.precision(.fractionLength(0)).locale(locale))
    }
}

extension Int {
    /// A game count with the locale's grouping ("8.212" in es-AR).
    func countText(locale: Locale = .current) -> String {
        formatted(.number.locale(locale))
    }
}
