import AppKit
import Testing

@testable import Mito

/// Semantic color stays legible: at least 4.5:1 on white in light mode, the system color in dark
/// (§22.1).
struct ReadableColorTests {
    nonisolated static let colors: [(NSColor, NSColor)] = [
        (.favorable, .systemGreen), (.unfavorable, .systemRed), (.caution, .systemOrange),
        (.mintReadable, .systemMint),
    ]

    @Test(arguments: colors)
    func lightAppearanceReachesTextContrastOnWhite(color: NSColor, system: NSColor) throws {
        let light = try #require(NSAppearance(named: .aqua))
        let resolved = try #require(Self.sRGB(color, in: light))
        #expect(Self.contrast(resolved, .white) >= 4.5)
    }

    @Test(arguments: colors)
    func darkAppearanceKeepsTheSystemColor(color: NSColor, system: NSColor) throws {
        let dark = try #require(NSAppearance(named: .darkAqua))
        let resolved = try #require(Self.sRGB(color, in: dark))
        let expected = try #require(Self.sRGB(system, in: dark))
        #expect(abs(resolved.redComponent - expected.redComponent) < 0.001)
        #expect(abs(resolved.greenComponent - expected.greenComponent) < 0.001)
        #expect(abs(resolved.blueComponent - expected.blueComponent) < 0.001)
    }

    private static func sRGB(_ color: NSColor, in appearance: NSAppearance) -> NSColor? {
        var resolved: NSColor?
        appearance.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.sRGB)
        }
        return resolved
    }

    private static func contrast(_ first: NSColor, _ second: NSColor) -> Double {
        let lighter = max(luminance(first), luminance(second))
        let darker = min(luminance(first), luminance(second))
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func luminance(_ color: NSColor) -> Double {
        func channel(_ value: CGFloat) -> Double {
            let value = Double(value)
            return value <= 0.039_28 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let rgb = color.usingColorSpace(.sRGB) ?? color
        return 0.2126 * channel(rgb.redComponent) + 0.7152 * channel(rgb.greenComponent)
            + 0.0722 * channel(rgb.blueComponent)
    }
}
