import Foundation
import MitoCore
import Testing

@testable import MitoStore

extension SnapshotDownloaderTests {
    /// Nested so it inherits the parent's `.serialized`: both suites share `RoutingURLProtocol`.
    @Suite struct TipsDownloadTests {
        private static let baseURL = "https://snapshots.test/"
        private static let bundleIdentifier = "com.joacominatel.mito.tests"
        private static let tipsURL = "https://data.example/tips/1/es-AR.json"
        private static let ahri = ChampionID(rawValue: 103)
        private static let zed = ChampionID(rawValue: 238)

        // MARK: Happy path

        @Test func downloadsVerifiesAndReadsTheContractFixture() async throws {
            try await withCaches { caches in
                try Self.serve(manifest: SnapshotFixture.manifest)
                let tips = try await downloader(caches).installCurrentTips(locale: "es-AR")

                #expect(tips.records.count == 3)
                #expect(
                    tips.tips(for: Self.ahri, role: .middle, against: Self.zed).first?.text
                        == "Synthetic tip: hold E until Zed commits his R.")
            }
        }

        @Test func theFileIsCachedVerbatimUnderTheBundleIdentifierAndLocale() async throws {
            try await withCaches { caches in
                try Self.serve(manifest: SnapshotFixture.manifest)
                let downloader = try downloader(caches)
                _ = try await downloader.installCurrentTips(locale: "es-AR")

                let file = caches.appending(path: "\(Self.bundleIdentifier)/tips/es-AR.json")
                #expect(try Data(contentsOf: file) == SnapshotFixture.tips)
                #expect(
                    downloader.tipsDirectory.standardizedFileURL
                        == caches.appending(path: "\(Self.bundleIdentifier)/tips")
                        .standardizedFileURL)
            }
        }

        @Test func installedTipsAreFoundAgainWithoutTheNetwork() async throws {
            try await withCaches { caches in
                try Self.serve(manifest: SnapshotFixture.manifest)
                let installed = try await downloader(caches).installCurrentTips(locale: "es-AR")
                RoutingURLProtocol.serve([:])

                let reopened = try downloader(caches)
                #expect(await reopened.installedTips(locale: "es-AR") == installed)
                #expect(RoutingURLProtocol.received.isEmpty)
            }
        }

        @Test func nothingIsInstalledBeforeTheFirstDownload() async throws {
            try await withCaches { caches in
                let downloader = try downloader(caches)
                #expect(await downloader.installedTips(locale: "es-AR") == .empty)
            }
        }

        // MARK: Cadence

        @Test func theSameSHAIsNotDownloadedAgain() async throws {
            try await withCaches { caches in
                let downloader = try downloader(caches)
                try Self.serve(manifest: SnapshotFixture.manifest)
                let first = try await downloader.installCurrentTips(locale: "es-AR")
                try Self.serve(manifest: SnapshotFixture.manifest)

                #expect(try await downloader.installCurrentTips(locale: "es-AR") == first)
                #expect(
                    RoutingURLProtocol.received.map(\.absoluteString) == [
                        "\(Self.baseURL)manifest.json"
                    ])
            }
        }

        @Test func aDifferentSHAReplacesTheInstalledFile() async throws {
            try await withCaches { caches in
                let downloader = try downloader(caches)
                try Self.serve(manifest: SnapshotFixture.manifest)
                _ = try await downloader.installCurrentTips(locale: "es-AR")

                let updated = Self.tipsFile(text: "Updated tip.")
                try Self.serve(
                    manifest: Self.manifest(tips: [Self.entry(for: updated)]),
                    tips: updated)
                let tips = try await downloader.installCurrentTips(locale: "es-AR")

                #expect(tips.records.map(\.text) == ["Updated tip."])
                #expect(await downloader.installedTips(locale: "es-AR") == tips)
            }
        }

        // MARK: Failures keep the previous file

        @Test func aSHAMismatchKeepsThePreviousTips() async throws {
            try await withCaches { caches in
                let downloader = try downloader(caches)
                let previous = try await installFixture(downloader)

                let tampered = Self.tipsFile(text: "Tampered tip.")
                var entry = Self.entry(for: tampered)
                entry["sha256"] = String(repeating: "0", count: 64)
                try Self.serve(manifest: Self.manifest(tips: [entry]), tips: tampered)

                #expect(await failure(downloader) == .checksumMismatch)
                #expect(await downloader.installedTips(locale: "es-AR") == previous)
            }
        }

        @Test func aFailedDownloadKeepsThePreviousTips() async throws {
            try await withCaches { caches in
                let downloader = try downloader(caches)
                let previous = try await installFixture(downloader)

                let updated = Self.tipsFile(text: "Updated tip.")
                try Self.serveWithoutTips(manifest: Self.manifest(tips: [Self.entry(for: updated)]))

                #expect(await failure(downloader) == .downloadFailed("HTTP 404"))
                #expect(await downloader.installedTips(locale: "es-AR") == previous)
            }
        }

        @Test(arguments: [-1, 1])
        func aFileOtherThanTheManifestBytesIsASizeMismatch(_ delta: Int) async throws {
            try await withCaches { caches in
                var entry = try Self.fixtureEntry()
                entry["bytes"] = SnapshotFixture.tips.count + delta
                try Self.serve(manifest: Self.manifest(tips: [entry]))

                let failure = await failure(try downloader(caches))
                guard case .sizeMismatch(let expected, _) = failure else {
                    Issue.record("expected a size mismatch, got \(String(describing: failure))")
                    return
                }
                #expect(expected == SnapshotFixture.tips.count + delta)
            }
        }

        @Test func aVerifiedFileThatIsNotTheContractShapeKeepsThePreviousTips() async throws {
            try await withCaches { caches in
                let downloader = try downloader(caches)
                let previous = try await installFixture(downloader)

                let broken = Data(#"{"format_version": 1, "locale": "es-AR"}"#.utf8)
                try Self.serve(
                    manifest: Self.manifest(tips: [Self.entry(for: broken)]), tips: broken)

                #expect(await failure(downloader) == .tipsInvalid)
                #expect(await downloader.installedTips(locale: "es-AR") == previous)
            }
        }

        @Test func aFileForAnotherLocaleThanItsEntryIsInvalid() async throws {
            try await withCaches { caches in
                let english = Data(
                    #"{"format_version": 1, "locale": "en-US", "tips": []}"#.utf8)
                try Self.serve(
                    manifest: Self.manifest(tips: [Self.entry(for: english)]), tips: english)

                #expect(await failure(try downloader(caches)) == .tipsInvalid)
            }
        }

        @Test func anUnreachableManifestKeepsThePreviousTips() async throws {
            try await withCaches { caches in
                let downloader = try downloader(caches)
                let previous = try await installFixture(downloader)
                RoutingURLProtocol.serve([:])

                #expect(await failure(downloader) == .manifestUnreachable("HTTP 404"))
                #expect(await downloader.installedTips(locale: "es-AR") == previous)
            }
        }

        // MARK: No entry

        @Test func noTipsEntryMeansNoTipsAndNoError() async throws {
            try await withCaches { caches in
                try Self.serve(manifest: Self.manifest(tips: nil))

                #expect(try await downloader(caches).installCurrentTips(locale: "es-AR") == .empty)
                #expect(
                    RoutingURLProtocol.received.map(\.absoluteString) == [
                        "\(Self.baseURL)manifest.json"
                    ])
            }
        }

        @Test func onlyAnUnsupportedFormatVersionMeansNoTipsAndNoRequest() async throws {
            try await withCaches { caches in
                try Self.serve(
                    manifest: Self.manifest(tips: [try Self.fixtureEntry(["format_version": 2])]))

                #expect(try await downloader(caches).installCurrentTips(locale: "es-AR") == .empty)
                #expect(!RoutingURLProtocol.received.contains { $0.absoluteString == Self.tipsURL })
            }
        }

        @Test func aLocaleTheManifestDoesNotListHasNoTips() async throws {
            try await withCaches { caches in
                try Self.serve(manifest: SnapshotFixture.manifest)

                #expect(try await downloader(caches).installCurrentTips(locale: "en-US") == .empty)
            }
        }

        @Test func tipsWithdrawnFromTheManifestAreRemoved() async throws {
            try await withCaches { caches in
                let downloader = try downloader(caches)
                _ = try await installFixture(downloader)
                try Self.serve(manifest: Self.manifest(tips: []))

                #expect(try await downloader.installCurrentTips(locale: "es-AR") == .empty)
                #expect(await downloader.installedTips(locale: "es-AR") == .empty)
            }
        }

        // MARK: Security and limits

        @Test func anEntryURLThatIsNotHTTPSIsNotRequested() async throws {
            try await withCaches { caches in
                let plain = "http://data.example/tips/1/es-AR.json"
                try Self.serve(
                    manifest: Self.manifest(tips: [try Self.fixtureEntry(["url": plain])]))

                #expect(await failure(try downloader(caches)) == .insecureURL)
                #expect(!RoutingURLProtocol.received.contains { $0.absoluteString == plain })
            }
        }

        @Test func bytesAboveTheLimitAreRefusedBeforeDownloading() async throws {
            try await withCaches { caches in
                try Self.serve(
                    manifest: Self.manifest(tips: [
                        try Self.fixtureEntry(["bytes": CuratedTips.sizeLimit + 1])
                    ]))

                #expect(await failure(try downloader(caches)) == .sizeLimitExceeded)
                #expect(!RoutingURLProtocol.received.contains { $0.absoluteString == Self.tipsURL })
            }
        }

        @Test func aLocaleThatIsNotALanguageTagIsNeverAFileName() async throws {
            try await withCaches { caches in
                let escape = "../../escape"
                let file = Data(
                    #"{"format_version": 1, "locale": "\#(escape)", "tips": []}"#.utf8)
                var entry = Self.entry(for: file)
                entry["locale"] = escape
                try Self.serve(manifest: Self.manifest(tips: [entry]), tips: file)

                #expect(await failure(try downloader(caches), locale: escape) == .installFailed)
                #expect(
                    !FileManager.default.fileExists(
                        atPath: caches.appending(path: "escape.json").path))
            }
        }

        // MARK: Helpers

        private func downloader(_ caches: URL) throws -> SnapshotDownloader {
            try SnapshotDownloader(
                baseURL: Self.baseURL, bundleIdentifier: Self.bundleIdentifier,
                cachesDirectory: caches, configuration: RoutingURLProtocol.configuration())
        }

        private func installFixture(_ downloader: SnapshotDownloader) async throws -> CuratedTips {
            try Self.serve(manifest: SnapshotFixture.manifest)
            let tips = try await downloader.installCurrentTips(locale: "es-AR")
            try #require(tips.records.count == 3)
            return tips
        }

        private func failure(_ downloader: SnapshotDownloader, locale: String = "es-AR") async
            -> SnapshotDownloadError?
        {
            do {
                _ = try await downloader.installCurrentTips(locale: locale)
                return nil
            } catch {
                return error
            }
        }

        private static func serve(manifest: Data, tips: Data = SnapshotFixture.tips) throws {
            RoutingURLProtocol.serve([
                try #require(URL(string: "\(baseURL)manifest.json")): .response(
                    status: 200, body: manifest),
                try #require(URL(string: tipsURL)): .response(status: 200, body: tips),
            ])
        }

        private static func serveWithoutTips(manifest: Data) throws {
            RoutingURLProtocol.serve([
                try #require(URL(string: "\(baseURL)manifest.json")): .response(
                    status: 200, body: manifest)
            ])
        }

        private static func tipsFile(text: String) -> Data {
            Data(
                #"{"format_version": 1, "locale": "es-AR", "tips": [{"champion_id": 103, "role": "MIDDLE", "opp_id": 0, "reviewed_patch": "16.21", "text": "\#(text)"}]}"#
                    .utf8)
        }

        private static func entry(for file: Data) -> [String: Any] {
            [
                "format_version": 1, "locale": "es-AR", "url": tipsURL,
                "sha256": SnapshotArchive.sha256Hex(file), "bytes": file.count,
                "updated_at": "2026-10-21T12:00:00Z",
            ]
        }

        private static func fixtureEntry(_ overrides: [String: Any] = [:]) throws -> [String: Any] {
            let root = try #require(
                try JSONSerialization.jsonObject(with: SnapshotFixture.manifest) as? [String: Any])
            let entry = try #require((root["tips"] as? [[String: Any]])?.first)
            return entry.merging(overrides) { _, override in override }
        }

        private static func manifest(tips: [[String: Any]]?) throws -> Data {
            var root = try #require(
                try JSONSerialization.jsonObject(with: SnapshotFixture.manifest) as? [String: Any])
            if let tips { root["tips"] = tips } else { root.removeValue(forKey: "tips") }
            return try JSONSerialization.data(withJSONObject: root)
        }

        private func withCaches(_ body: (URL) async throws -> Void) async throws {
            let caches = FileManager.default.temporaryDirectory
                .appending(
                    path: "TipsDownloadTests-\(UUID().uuidString)", directoryHint: .isDirectory)
            defer { try? FileManager.default.removeItem(at: caches) }
            try await body(caches)
        }
    }
}
