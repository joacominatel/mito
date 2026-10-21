import Foundation
import SwiftUI

/// The direction a number points. Color always comes with its sign or icon (§22.1).
nonisolated enum Tone: Hashable {
    case favorable
    case unfavorable
    case neutral

    var color: Color {
        switch self {
        case .favorable: .green
        case .unfavorable: .red
        case .neutral: .secondary
        }
    }
}

/// Fractions as the UI reads them (§18.3): `0.021` is "+2,1" winrate points.
enum WinratePoints {
    /// To the one decimal the UI shows, so the sign and the text never disagree.
    static func rounded(_ delta: Double) -> Double {
        (delta * 1000).rounded() / 10
    }

    /// Signed, one decimal; zero after rounding has no sign. The minus is U+2212.
    static func text(_ delta: Double, locale: Locale = .current) -> String {
        let points = rounded(delta)
        let magnitude = abs(points).formatted(.number.precision(.fractionLength(1)).locale(locale))
        if points > 0 { return "+" + magnitude }
        if points < 0 { return "\u{2212}" + magnitude }
        return magnitude
    }

    static func tone(_ delta: Double) -> Tone {
        let points = rounded(delta)
        return points > 0 ? .favorable : points < 0 ? .unfavorable : .neutral
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
