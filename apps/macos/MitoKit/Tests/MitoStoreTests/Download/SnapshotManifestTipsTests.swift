import Foundation
import Testing

@testable import MitoStore

struct SnapshotManifestTipsTests {
    @Test func theContractManifestListsTheTipsFile() throws {
        let manifest = try SnapshotManifest.decode(SnapshotFixture.manifest)

        #expect(
            manifest.tips == [
                SnapshotManifest.TipsEntry(
                    formatVersion: 1, locale: "es-AR",
                    url: try #require(URL(string: "https://data.example/tips/1/es-AR.json")),
                    sha256: "f224457ce9d2f8c21e8811545318b91fbaae379151245cca3b1654f13ecb4165",
                    bytes: 598, updatedAt: "2026-10-20T12:00:00Z")
            ])
    }

    @Test func theContractManifestEntryDescribesTheCommittedTipsFile() throws {
        let entry = try #require(
            try SnapshotManifest.decode(SnapshotFixture.manifest).tipsEntry(
                locale: "es-AR", supportedFormatVersions: 1...1))

        #expect(entry.bytes == SnapshotFixture.tips.count)
        #expect(entry.sha256 == SnapshotArchive.sha256Hex(SnapshotFixture.tips))
    }

    @Test func aManifestWithoutTipsHasNoTipsAndKeepsItsSnapshots() throws {
        let manifest = try SnapshotManifest.decode(manifest(tips: nil))

        #expect(manifest.tips.isEmpty)
        #expect(manifest.snapshots.count == 1)
    }

    @Test func tipsThatAreNotAListDoNotBreakTheSnapshots() throws {
        let manifest = try SnapshotManifest.decode(manifest(tips: "soon"))

        #expect(manifest.tips.isEmpty)
        #expect(manifest.snapshots.count == 1)
    }

    @Test func aMalformedTipsEntryIsDroppedAndTheOthersKept() throws {
        let manifest = try SnapshotManifest.decode(
            manifest(tips: [try fixtureTipsEntry(["sha256": 42]), try fixtureTipsEntry()]))

        #expect(manifest.tips.count == 1)
    }

    @Test func anEntryWithAnUnsupportedFormatVersionIsIgnored() throws {
        let manifest = try SnapshotManifest.decode(
            manifest(tips: [
                try fixtureTipsEntry(["format_version": 2, "layout": "new"]),
                try fixtureTipsEntry(),
            ]))

        #expect(
            manifest.tipsEntry(locale: "es-AR", supportedFormatVersions: 1...1)?.formatVersion
                == 1)
    }

    @Test func onlyUnsupportedFormatVersionsMeanNoTips() throws {
        let manifest = try SnapshotManifest.decode(
            manifest(tips: [try fixtureTipsEntry(["format_version": 2])]))

        #expect(manifest.tipsEntry(locale: "es-AR", supportedFormatVersions: 1...1) == nil)
    }

    @Test func anEntryForAnotherLocaleIsNotChosen() throws {
        let manifest = try SnapshotManifest.decode(SnapshotFixture.manifest)

        #expect(manifest.tipsEntry(locale: "en-US", supportedFormatVersions: 1...1) == nil)
    }

    // MARK: Helpers

    private func fixtureTipsEntry(_ overrides: [String: Any] = [:]) throws -> [String: Any] {
        let root = try #require(
            try JSONSerialization.jsonObject(with: SnapshotFixture.manifest) as? [String: Any])
        let entry = try #require((root["tips"] as? [[String: Any]])?.first)
        return entry.merging(overrides) { _, override in override }
    }

    private func manifest(tips: Any?) throws -> Data {
        var root = try #require(
            try JSONSerialization.jsonObject(with: SnapshotFixture.manifest) as? [String: Any])
        root["tips"] = tips
        return try JSONSerialization.data(withJSONObject: root)
    }
}
