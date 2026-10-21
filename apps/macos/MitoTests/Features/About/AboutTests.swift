import Foundation
import MitoCore
import Testing

@testable import Mito

struct AboutTests {
    static let meta = SnapshotMeta(
        patch: Patch(rawValue: "16.21"), queue: QueueID(rawValue: 420), bracket: .emeraldPlus,
        matches: 412_339, blendPatches: [Patch(rawValue: "16.21")], thresholds: [:],
        priors: SmoothingPriors(
            championRoleStrength: 100, championRoleBaseline: 0.5, relationStrength: 200,
            loadoutStrength: 500),
        tierCutoffs: [:])

    @Test func versionShowsTheMarketingVersionAndTheBuild() {
        let info = ["CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "7"]

        #expect(About.version(info: info) == "Versión 0.1.0 (7)")
    }

    @Test func versionMarksMissingKeysInsteadOfDroppingThem() {
        #expect(About.version(info: nil) == "Versión — (—)")
    }

    @Test func nameIsTheBundleDisplayNameSoDebugReadsAsSuch() {
        #expect(
            About.name(info: ["CFBundleDisplayName": "Mito Dev", "CFBundleName": "Mito"])
                == "Mito Dev")
        #expect(About.name(info: ["CFBundleName": "Mito"]) == "Mito")
        #expect(About.name(info: nil) == "Mito")
    }

    @Test func snapshotLineShowsThePatchAndTheLocaleFormattedMatchCount() {
        let line = About.snapshotLine(Self.meta, locale: Locale(identifier: "es_AR"))

        #expect(line == "Parche 16.21 · 412.339 partidas")
    }

    @Test func snapshotLineSaysThereAreNoStatsWithoutASnapshot() {
        #expect(About.snapshotLine(nil) == "Sin estadísticas")
    }

    @Test func disclaimerIsTheSection5TextVerbatim() throws {
        let context = try String(contentsOf: Self.mitoContext, encoding: .utf8)
        let lines = context.components(separatedBy: "\n")
        let item = try #require(lines.firstIndex { $0.contains("**Disclaimer legal**") })
        let quote = lines[(item + 1)...]
            .prefix { $0.trimmingCharacters(in: .whitespaces).hasPrefix(">") }
            .map {
                $0.trimmingCharacters(in: .whitespaces).dropFirst().trimmingCharacters(
                    in: .whitespaces)
            }

        #expect(!quote.isEmpty)
        #expect(About.riotDisclaimer == quote.joined(separator: " "))
    }

    @Test func grdbNoticeCarriesItsMITLicenseText() {
        let grdb = About.notices.first { $0.name == "GRDB.swift" }

        #expect(grdb?.license == "MIT")
        #expect(grdb?.text.hasPrefix("Copyright (C) 2015-2025 Gwendal Roué") == true)
        #expect(grdb?.text.contains("shall be included in all copies") == true)
    }

    @Test func sparkleNoticeCarriesItsLicenseAndTheBundledComponents() {
        let sparkle = About.notices.first { $0.name == "Sparkle" }

        #expect(sparkle?.license == "MIT")
        #expect(sparkle?.text.hasPrefix("Copyright (c) 2006-2013 Andy Matuschak.") == true)
        #expect(sparkle?.text.contains("shall be included in all") == true)
        #expect(sparkle?.text.contains("bsdiff") == true)
        #expect(sparkle?.text.contains("Ed25519") == true)
    }

    private static let mitoContext = URL(filePath: #filePath)
        .deletingLastPathComponent()  // About/
        .deletingLastPathComponent()  // Features/
        .deletingLastPathComponent()  // MitoTests/
        .deletingLastPathComponent()  // macos/
        .deletingLastPathComponent()  // apps/
        .deletingLastPathComponent()  // repository root
        .appending(path: "MITO_CONTEXT.md", directoryHint: .notDirectory)
}
