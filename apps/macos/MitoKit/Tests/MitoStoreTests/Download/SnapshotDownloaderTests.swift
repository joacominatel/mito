import Foundation
import MitoCore
import Testing

@testable import MitoStore

@Suite(.serialized)
struct SnapshotDownloaderTests {
    private static let baseURL = "https://snapshots.test/"
    private static let bundleIdentifier = "com.joacominatel.mito.tests"
    private static let rankedSolo = QueueID(rawValue: 420)
    private static let fixtureFileURL =
        "https://data.example/schema-1/16.21/420/emerald_plus.sqlite.xz"

    // MARK: Happy path

    @Test func theEmbeddedManifestDescribesTheEmbeddedArchive() throws {
        let entry = try Self.fixtureEntry()
        #expect(entry["bytes"] as? Int == SnapshotFixture.compressed.count)
        #expect(entry["sha256"] as? String == sha256(SnapshotFixture.compressed))
        #expect(entry["raw_bytes"] as? Int == SnapshotFixture.sqliteBytes)
    }

    @Test func installsThePipelineFixtureAsItsDecompressedSQLite() async throws {
        try await withCaches { caches in
            try Self.serveFixture()
            let installed = try await downloader(caches).installCurrent(
                queue: Self.rankedSolo, bracket: .emeraldPlus)

            #expect(installed.patch == Patch(rawValue: "16.21"))
            #expect(installed.schemaVersion == 1)
            #expect(installed.matches == 20000)
            let written = try Data(contentsOf: installed.fileURL)
            #expect(written.count == SnapshotFixture.sqliteBytes)
            #expect(sha256(written) == SnapshotFixture.sqliteSHA256)
        }
    }

    @Test func theFileLandsUnderTheBundleIdentifierAndTheSnapshotIdentity() async throws {
        try await withCaches { caches in
            try Self.serveFixture()
            let installed = try await downloader(caches).installCurrent(
                queue: Self.rankedSolo, bracket: .emeraldPlus)

            let expected = caches.appending(
                path: "\(Self.bundleIdentifier)/snapshots/schema-1/16.21/420/emerald_plus.sqlite")
            #expect(installed.fileURL.standardizedFileURL == expected.standardizedFileURL)
        }
    }

    @Test func requestsTheManifestFromTheBaseURLThenTheEntryURL() async throws {
        try await withCaches { caches in
            try Self.serveFixture()
            _ = try await downloader(caches).installCurrent(
                queue: Self.rankedSolo, bracket: .emeraldPlus)

            #expect(
                RoutingURLProtocol.received.map(\.absoluteString) == [
                    "https://snapshots.test/manifest.json", Self.fixtureFileURL,
                ])
        }
    }

    @Test func theInstalledSnapshotIsFoundAgainWithoutTheNetwork() async throws {
        try await withCaches { caches in
            try Self.serveFixture()
            let installed = try await downloader(caches).installCurrent(
                queue: Self.rankedSolo, bracket: .emeraldPlus)
            RoutingURLProtocol.serve([:])

            let reopened = try downloader(caches)
            #expect(
                await reopened.installedSnapshot(queue: Self.rankedSolo, bracket: .emeraldPlus)
                    == installed)
            #expect(RoutingURLProtocol.received.isEmpty)
        }
    }

    @Test func nothingIsInstalledBeforeTheFirstDownload() async throws {
        try await withCaches { caches in
            let downloader = try downloader(caches)
            #expect(
                await downloader.installedSnapshot(queue: Self.rankedSolo, bracket: .emeraldPlus)
                    == nil)
        }
    }

    // MARK: Manifest

    @Test func anEntryWithAnUnsupportedSchemaVersionIsIgnored() async throws {
        try await withCaches { caches in
            let future: [String: Any] = [
                "schema_version": 2, "patch": "16.21", "queue": 420, "bracket": "emerald_plus",
                "url": "https://data.example/schema-2/16.21/420/emerald_plus.sqlite.zst",
                "layout": ["something": "new"],
            ]
            try Self.serve(manifest: Self.manifest(entries: [future, Self.fixtureEntry()]))
            let installed = try await downloader(caches).installCurrent(
                queue: Self.rankedSolo, bracket: .emeraldPlus)

            #expect(installed.schemaVersion == 1)
            #expect(
                !RoutingURLProtocol.received.map(\.absoluteString).contains {
                    $0.contains("schema-2")
                })
        }
    }

    @Test func onlyUnsupportedEntriesMeanNoMatchingSnapshot() async throws {
        try await withCaches { caches in
            try Self.serve(
                manifest: Self.manifest(entries: [Self.fixtureEntry(["schema_version": 2])]))

            #expect(await failure(try downloader(caches)) == .noMatchingSnapshot)
        }
    }

    @Test func theHighestSupportedSchemaVersionWins() async throws {
        try await withCaches { caches in
            let v2URL = "https://data.example/schema-2/16.21/420/emerald_plus.sqlite.xz"
            try Self.serve(
                manifest: Self.manifest(entries: [
                    Self.fixtureEntry(), Self.fixtureEntry(["schema_version": 2, "url": v2URL]),
                ]),
                files: [v2URL: SnapshotFixture.compressed])
            let downloader = try SnapshotDownloader(
                baseURL: Self.baseURL, supportedSchemaVersions: 1...2,
                bundleIdentifier: Self.bundleIdentifier, cachesDirectory: caches,
                configuration: RoutingURLProtocol.configuration())

            let installed = try await downloader.installCurrent(
                queue: Self.rankedSolo, bracket: .emeraldPlus)
            #expect(installed.schemaVersion == 2)
            #expect(installed.fileURL.path.contains("/schema-2/16.21/"))
        }
    }

    @Test(arguments: [(440, Bracket.emeraldPlus), (420, Bracket.diamondPlus)])
    func noEntryForTheQueueOrBracketMeansNoMatchingSnapshot(queue: Int, bracket: Bracket)
        async throws
    {
        try await withCaches { caches in
            try Self.serveFixture()

            let error = await failure(
                try downloader(caches), queue: QueueID(rawValue: queue), bracket: bracket)
            #expect(error == .noMatchingSnapshot)
        }
    }

    @Test func anEntryForAnotherPatchThanTheCurrentOneIsNotChosen() async throws {
        try await withCaches { caches in
            try Self.serve(
                manifest: Self.manifest(currentPatch: "16.22", entries: [Self.fixtureEntry()]))

            #expect(await failure(try downloader(caches)) == .noMatchingSnapshot)
        }
    }

    @Test func aManifestServerErrorIsUnreachable() async throws {
        try await withCaches { caches in
            RoutingURLProtocol.serve([:])

            guard case .manifestUnreachable = await failure(try downloader(caches)) else {
                Issue.record("expected manifestUnreachable")
                return
            }
        }
    }

    @Test(arguments: [
        #"not json"#,
        #"{"snapshots": []}"#,
        #"{"current_patch": "../../Library", "snapshots": []}"#,
    ])
    func aManifestThatIsNotTheContractShapeIsInvalid(_ body: String) async throws {
        try await withCaches { caches in
            try Self.serve(manifest: Data(body.utf8))

            #expect(await failure(try downloader(caches)) == .manifestInvalid)
        }
    }

    @Test func anEntryWhosePatchIsNotAPatchIsIgnored() async throws {
        try await withCaches { caches in
            try Self.serve(
                manifest: Self.manifest(
                    currentPatch: "16.21", entries: [Self.fixtureEntry(["patch": "../16.21"])]))

            #expect(await failure(try downloader(caches)) == .noMatchingSnapshot)
        }
    }

    // MARK: Verification

    @Test func aSHAMismatchInstallsNothingAndKeepsThePreviousSnapshot() async throws {
        try await withCaches { caches in
            let downloader = try downloader(caches)
            let previous = try await installFixture(downloader)

            try Self.serve(
                manifest: Self.manifest(
                    currentPatch: "16.22",
                    entries: [
                        Self.fixtureEntry([
                            "patch": "16.22", "sha256": String(repeating: "0", count: 64),
                        ])
                    ]))
            #expect(await failure(downloader) == .checksumMismatch)

            #expect(
                await downloader.installedSnapshot(queue: Self.rankedSolo, bracket: .emeraldPlus)
                    == previous)
            #expect(sha256(try Data(contentsOf: previous.fileURL)) == SnapshotFixture.sqliteSHA256)
            #expect(
                !FileManager.default.fileExists(
                    atPath: Self.snapshotsRoot(caches).appending(path: "schema-1/16.22").path))
        }
    }

    @Test(arguments: [-1, 1])
    func aCompressedSizeOtherThanTheManifestBytesIsASizeMismatch(_ delta: Int) async throws {
        try await withCaches { caches in
            let expected = SnapshotFixture.compressed.count + delta
            try Self.serve(
                manifest: Self.manifest(entries: [Self.fixtureEntry(["bytes": expected])]))

            let error = await failure(try downloader(caches))
            let actual = SnapshotFixture.compressed.count
            #expect(error == .sizeMismatch(expected: expected, actual: actual))
        }
    }

    @Test(arguments: [
        Data("not an xz stream at all".utf8), SnapshotFixture.compressed.prefix(4000),
    ])
    func anArchiveThatIsNotValidXZFailsToDecompress(_ archive: Data) async throws {
        try await withCaches { caches in
            try Self.serve(
                manifest: Self.manifest(entries: [
                    Self.fixtureEntry(["bytes": archive.count, "sha256": sha256(archive)])
                ]),
                files: [Self.fixtureFileURL: archive])

            let downloader = try downloader(caches)
            #expect(await failure(downloader) == .decompressionFailed)
            #expect(
                await downloader.installedSnapshot(queue: Self.rankedSolo, bracket: .emeraldPlus)
                    == nil)
        }
    }

    @Test func aDecompressedSizeOtherThanRawBytesIsRejected() async throws {
        try await withCaches { caches in
            try Self.serve(
                manifest: Self.manifest(entries: [Self.fixtureEntry(["raw_bytes": 100_000])]))

            let downloader = try downloader(caches)
            #expect(
                await failure(downloader)
                    == .decompressedSizeMismatch(
                        expected: 100_000, actual: SnapshotFixture.sqliteBytes))
            #expect(
                await downloader.installedSnapshot(queue: Self.rankedSolo, bracket: .emeraldPlus)
                    == nil)
        }
    }

    @Test func decodingStopsAtTheUncompressedLimitEvenWhenRawBytesClaimsLess() async throws {
        try await withCaches { caches in
            try Self.serve(
                manifest: Self.manifest(entries: [Self.fixtureEntry(["raw_bytes": 50_000])]))

            let downloader = try downloader(caches, decompressedSizeLimit: 60_000)
            #expect(await failure(downloader) == .sizeLimitExceeded)
            #expect(
                await downloader.installedSnapshot(queue: Self.rankedSolo, bracket: .emeraldPlus)
                    == nil)
        }
    }

    @Test func rawBytesAboveTheLimitAreRefusedBeforeDownloading() async throws {
        try await withCaches { caches in
            try Self.serve(
                manifest: Self.manifest(entries: [
                    Self.fixtureEntry(["raw_bytes": 32 * 1024 * 1024 + 1])
                ]))

            #expect(await failure(try downloader(caches)) == .sizeLimitExceeded)
            #expect(
                RoutingURLProtocol.received.map(\.absoluteString) == [
                    "https://snapshots.test/manifest.json"
                ])
        }
    }

    @Test func compressedBytesAboveTheLimitAreRefusedBeforeDownloading() async throws {
        try await withCaches { caches in
            try Self.serve(
                manifest: Self.manifest(entries: [Self.fixtureEntry(["bytes": 8 * 1024 * 1024 + 1])]
                ))

            #expect(await failure(try downloader(caches)) == .sizeLimitExceeded)
            #expect(RoutingURLProtocol.received.count == 1)
        }
    }

    // MARK: Cache

    @Test func anAlreadyCurrentFileIsNotDownloadedAgain() async throws {
        try await withCaches { caches in
            let downloader = try downloader(caches)
            let first = try await installFixture(downloader)
            try Self.serveFixture()

            let second = try await downloader.installCurrent(
                queue: Self.rankedSolo, bracket: .emeraldPlus)
            #expect(second == first)
            #expect(
                RoutingURLProtocol.received.map(\.absoluteString) == [
                    "https://snapshots.test/manifest.json"
                ])
        }
    }

    @Test func aRepublishedFileForTheSamePatchIsDownloadedAgain() async throws {
        try await withCaches { caches in
            let downloader = try downloader(caches)
            _ = try await installFixture(downloader)
            try Self.serve(
                manifest: Self.manifest(entries: [
                    Self.fixtureEntry(["sha256": String(repeating: "f", count: 64)])
                ]))

            #expect(await failure(downloader) == .checksumMismatch)
            #expect(RoutingURLProtocol.received.map(\.absoluteString).contains(Self.fixtureFileURL))
        }
    }

    @Test func aNewPatchReplacesTheOldPatchFile() async throws {
        try await withCaches { caches in
            let downloader = try downloader(caches)
            let old = try await installFixture(downloader)
            try Self.serve(
                manifest: Self.manifest(
                    currentPatch: "16.22",
                    entries: [Self.fixtureEntry(["patch": "16.22", "matches": 3000])]))

            let new = try await downloader.installCurrent(
                queue: Self.rankedSolo, bracket: .emeraldPlus)
            #expect(new.patch == Patch(rawValue: "16.22"))
            #expect(new.matches == 3000)
            #expect(FileManager.default.fileExists(atPath: new.fileURL.path))
            #expect(!FileManager.default.fileExists(atPath: old.fileURL.path))
            #expect(
                !FileManager.default.fileExists(
                    atPath: Self.snapshotsRoot(caches).appending(path: "schema-1/16.21").path))
            #expect(
                await downloader.installedSnapshot(queue: Self.rankedSolo, bracket: .emeraldPlus)
                    == new)
        }
    }

    @Test func aLeftoverOlderPatchNeverShadowsTheNewerOne() async throws {
        try await withCaches { caches in
            let downloader = try downloader(caches)
            try Self.serve(
                manifest: Self.manifest(
                    currentPatch: "16.9", entries: [Self.fixtureEntry(["patch": "16.9"])]))
            let old = try await downloader.installCurrent(
                queue: Self.rankedSolo, bracket: .emeraldPlus)
            // A locked folder stands in for a cleanup that failed.
            let oldFolder = old.fileURL.deletingLastPathComponent()
            try Self.setImmutable(true, oldFolder)
            defer { try? Self.setImmutable(false, oldFolder) }
            try Self.serve(
                manifest: Self.manifest(
                    currentPatch: "16.10", entries: [Self.fixtureEntry(["patch": "16.10"])]))

            let new = try await downloader.installCurrent(
                queue: Self.rankedSolo, bracket: .emeraldPlus)

            try #require(FileManager.default.fileExists(atPath: old.fileURL.path))
            #expect(
                await downloader.installedSnapshot(queue: Self.rankedSolo, bracket: .emeraldPlus)
                    == new)
        }
    }

    @Test func replacingOneBracketLeavesTheOtherBracketAlone() async throws {
        try await withCaches { caches in
            let downloader = try downloader(caches)
            try Self.serve(
                manifest: Self.manifest(entries: [Self.fixtureEntry(["bracket": "diamond_plus"])]))
            let diamond = try await downloader.installCurrent(
                queue: Self.rankedSolo, bracket: .diamondPlus)

            try Self.serve(
                manifest: Self.manifest(
                    currentPatch: "16.22", entries: [Self.fixtureEntry(["patch": "16.22"])]))
            _ = try await downloader.installCurrent(queue: Self.rankedSolo, bracket: .emeraldPlus)

            #expect(FileManager.default.fileExists(atPath: diamond.fileURL.path))
            #expect(
                await downloader.installedSnapshot(queue: Self.rankedSolo, bracket: .diamondPlus)
                    == diamond)
        }
    }

    @Test func eachBundleIdentifierHasItsOwnCache() async throws {
        try await withCaches { caches in
            let release = try downloader(caches)
            let debug = try SnapshotDownloader(
                baseURL: Self.baseURL, bundleIdentifier: "\(Self.bundleIdentifier).debug",
                cachesDirectory: caches, configuration: RoutingURLProtocol.configuration())
            _ = try await installFixture(release)

            #expect(release.cacheDirectory != debug.cacheDirectory)
            #expect(
                debug.cacheDirectory.path.hasSuffix("/\(Self.bundleIdentifier).debug/snapshots"))
            #expect(
                await debug.installedSnapshot(queue: Self.rankedSolo, bracket: .emeraldPlus) == nil)
        }
    }

    @Test func aMissingBundleIdentifierFallsBackToTheAppIdentifier() async throws {
        try await withCaches { caches in
            let downloader = try SnapshotDownloader(
                baseURL: Self.baseURL, bundleIdentifier: nil, cachesDirectory: caches,
                configuration: RoutingURLProtocol.configuration())

            #expect(downloader.cacheDirectory.path.hasSuffix("/com.joacominatel.mito/snapshots"))
        }
    }

    @Test func anUnwritableCacheIsAnInstallFailure() async throws {
        try await withCaches { caches in
            let root = Self.snapshotsRoot(caches)
            try FileManager.default.createDirectory(
                at: root.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: root)
            try Self.serveFixture()

            #expect(await failure(try downloader(caches)) == .installFailed)
        }
    }

    // MARK: Transport security

    @Test(arguments: [
        "http://snapshots.test/", "ftp://snapshots.test/", "file:///tmp/", "snapshots.test",
    ])
    func aBaseURLThatIsNotHTTPSIsRefused(_ baseURL: String) throws {
        #expect(throws: SnapshotDownloadError.insecureURL) {
            try SnapshotDownloader(
                baseURL: baseURL, configuration: RoutingURLProtocol.configuration())
        }
    }

    @Test func theDefaultBaseURLIsHTTPS() throws {
        let downloader = try SnapshotDownloader()
        #expect(downloader.manifestURL.scheme == "https")
    }

    @Test func anEntryURLThatIsNotHTTPSIsNotRequested() async throws {
        try await withCaches { caches in
            let insecure = "http://data.example/schema-1/16.21/420/emerald_plus.sqlite.xz"
            try Self.serve(manifest: Self.manifest(entries: [Self.fixtureEntry(["url": insecure])]))

            #expect(await failure(try downloader(caches)) == .insecureURL)
            #expect(RoutingURLProtocol.received.count == 1)
        }
    }

    @Test func aRedirectToPlainHTTPIsNotFollowed() async throws {
        try await withCaches { caches in
            let manifestURL = try #require(URL(string: "https://snapshots.test/manifest.json"))
            let insecure = try #require(URL(string: "http://snapshots.test/manifest.json"))
            RoutingURLProtocol.serve([
                manifestURL: .redirect(to: insecure),
                insecure: .response(status: 200, body: SnapshotFixture.manifest),
            ])

            guard case .manifestUnreachable = await failure(try downloader(caches)) else {
                Issue.record("expected manifestUnreachable")
                return
            }
            #expect(!RoutingURLProtocol.received.contains(insecure))
        }
    }

    // MARK: Helpers

    private func downloader(_ caches: URL, decompressedSizeLimit: Int? = nil) throws
        -> SnapshotDownloader
    {
        try SnapshotDownloader(
            baseURL: Self.baseURL, supportedSchemaVersions: 1...1,
            bundleIdentifier: Self.bundleIdentifier, cachesDirectory: caches,
            configuration: RoutingURLProtocol.configuration(),
            decompressedSizeLimit: decompressedSizeLimit ?? 32 * 1024 * 1024)
    }

    private func installFixture(_ downloader: SnapshotDownloader) async throws -> InstalledSnapshot
    {
        try Self.serveFixture()
        return try await downloader.installCurrent(queue: Self.rankedSolo, bracket: .emeraldPlus)
    }

    private func failure(
        _ downloader: SnapshotDownloader, queue: QueueID = rankedSolo,
        bracket: Bracket = .emeraldPlus
    ) async -> SnapshotDownloadError? {
        do {
            _ = try await downloader.installCurrent(queue: queue, bracket: bracket)
            return nil
        } catch {
            return error
        }
    }

    private static func setImmutable(_ immutable: Bool, _ item: URL) throws {
        try FileManager.default.setAttributes([.immutable: immutable], ofItemAtPath: item.path)
    }

    private static func snapshotsRoot(_ caches: URL) -> URL {
        caches.appending(path: "\(bundleIdentifier)/snapshots", directoryHint: .isDirectory)
    }

    private static func serveFixture() throws {
        try serve(manifest: SnapshotFixture.manifest)
    }

    private static func serve(
        manifest: Data, files: [String: Data] = [fixtureFileURL: SnapshotFixture.compressed]
    ) throws {
        var routes: [URL: RoutingURLProtocol.Reply] = [
            try #require(URL(string: "\(baseURL)manifest.json")): .response(
                status: 200, body: manifest)
        ]
        for (url, body) in files {
            routes[try #require(URL(string: url))] = .response(status: 200, body: body)
        }
        RoutingURLProtocol.serve(routes)
    }

    /// The fixture's one snapshot entry, with `overrides` applied.
    private static func fixtureEntry(_ overrides: [String: Any] = [:]) throws -> [String: Any] {
        let root = try #require(
            try JSONSerialization.jsonObject(with: SnapshotFixture.manifest) as? [String: Any])
        let entries = try #require(root["snapshots"] as? [[String: Any]])
        let entry = try #require(entries.first)
        return entry.merging(overrides) { _, override in override }
    }

    private static func manifest(currentPatch: String = "16.21", entries: [[String: Any]]) throws
        -> Data
    {
        var root = try #require(
            try JSONSerialization.jsonObject(with: SnapshotFixture.manifest) as? [String: Any])
        root["current_patch"] = currentPatch
        root["snapshots"] = entries
        return try JSONSerialization.data(withJSONObject: root)
    }
}

private func sha256(_ data: Data) -> String {
    SnapshotArchive.sha256Hex(data)
}

private func withCaches(_ body: (URL) async throws -> Void) async throws {
    let caches = FileManager.default.temporaryDirectory
        .appending(
            path: "SnapshotDownloaderTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: caches) }
    try await body(caches)
}
