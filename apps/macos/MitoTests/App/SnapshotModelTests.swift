import Foundation
import MitoCore
import MitoStore
import Synchronization
import Testing

@testable import Mito

/// A cache and a download that never leave memory; files are named after their patch.
nonisolated final class FakeSnapshotSource: SnapshotSource {
    private let cached: URL?
    private let download: Result<URL, SnapshotDownloadError>
    private let installed: CuratedTips
    private let tipsDownload: Result<CuratedTips, SnapshotDownloadError>
    private let downloads = Mutex(0)

    init(
        cached: String?, download: Result<String, SnapshotDownloadError>,
        installedTips: CuratedTips = .empty,
        tipsDownload: Result<CuratedTips, SnapshotDownloadError> = .success(.empty)
    ) {
        self.cached = cached.map(Self.file)
        self.download = download.map(Self.file)
        installed = installedTips
        self.tipsDownload = tipsDownload
    }

    var downloadCount: Int { downloads.withLock { $0 } }

    func cachedFile() async -> URL? { cached }

    func downloadCurrent() async throws(SnapshotDownloadError) -> URL {
        downloads.withLock { $0 += 1 }
        return try download.get()
    }

    func installedTips() async -> CuratedTips { installed }

    func downloadCurrentTips() async throws(SnapshotDownloadError) -> CuratedTips {
        try tipsDownload.get()
    }

    private static func file(_ patch: String) -> URL {
        URL(filePath: "/snapshots/\(patch)", directoryHint: .notDirectory)
    }
}

private func model(_ source: FakeSnapshotSource) -> SnapshotModel {
    SnapshotModel(origin: .source(source), open: { PatchOnlyStats(patch: $0.lastPathComponent) })
}

struct SnapshotModelTests {
    @Test func opensTheCachedSnapshotAtStart() async {
        let source = FakeSnapshotSource(cached: "16.20", download: .failure(.noMatchingSnapshot))
        let snapshots = model(source)
        #expect(snapshots.meta == nil)

        await snapshots.run()

        #expect(snapshots.meta?.patch == Patch(rawValue: "16.20"))
        #expect(source.downloadCount == 1)
    }

    @Test func aSuccessfulDownloadSwapsTheProvider() async {
        let snapshots = model(FakeSnapshotSource(cached: "16.20", download: .success("16.21")))

        await snapshots.run()

        #expect(snapshots.meta?.patch == Patch(rawValue: "16.21"))
        #expect(snapshots.status == .ready)
    }

    @Test func aFailedDownloadKeepsTheCachedSnapshotAndOnlyRecordsIt() async {
        let failure = SnapshotDownloadError.manifestUnreachable("offline")
        let snapshots = model(FakeSnapshotSource(cached: "16.20", download: .failure(failure)))

        await snapshots.run()

        #expect(snapshots.meta?.patch == Patch(rawValue: "16.20"))
        #expect(snapshots.status == .failed(.download(failure)))
    }

    @Test func withoutACacheAFailedDownloadLeavesNoSnapshot() async {
        let snapshots = model(FakeSnapshotSource(cached: nil, download: .failure(.insecureURL)))

        await snapshots.run()

        #expect(snapshots.meta == nil)
        #expect(snapshots.status == .failed(.download(.insecureURL)))
    }

    @Test func anUnreadableCacheStillGetsTheDownload() async {
        let snapshots = SnapshotModel(
            origin: .source(FakeSnapshotSource(cached: "broken", download: .success("16.21"))),
            open: { url throws(SnapshotReadError) in
                guard url.lastPathComponent != "broken" else { throw .unreadable }
                return PatchOnlyStats(patch: url.lastPathComponent)
            })

        await snapshots.run()

        #expect(snapshots.meta?.patch == Patch(rawValue: "16.21"))
        #expect(snapshots.status == .ready)
    }

    @Test func anUnreadableDownloadKeepsTheCachedSnapshot() async {
        let snapshots = SnapshotModel(
            origin: .source(FakeSnapshotSource(cached: "16.20", download: .success("broken"))),
            open: { url throws(SnapshotReadError) in
                guard url.lastPathComponent != "broken" else { throw .unsupportedSchemaVersion(9) }
                return PatchOnlyStats(patch: url.lastPathComponent)
            })

        await snapshots.run()

        #expect(snapshots.meta?.patch == Patch(rawValue: "16.20"))
        #expect(snapshots.status == .failed(.unreadable(.unsupportedSchemaVersion(9))))
    }

    // MARK: Curated tips

    static func tips(_ text: String) -> CuratedTips {
        CuratedTips(records: [
            CuratedTipRecord(
                champion: ChampionID(rawValue: 103), role: .middle, opponent: nil,
                reviewedPatch: Patch(rawValue: "16.20"), text: text)
        ])
    }

    @Test func theInstalledTipsLoadAtLaunchAndTheCurrentOnesReplaceThem() async {
        let source = FakeSnapshotSource(
            cached: "16.20", download: .success("16.21"), installedTips: Self.tips("viejo"),
            tipsDownload: .success(Self.tips("nuevo")))
        let snapshots = model(source)

        await snapshots.run()

        #expect(snapshots.tips == Self.tips("nuevo"))
    }

    @Test func aFailedTipsInstallKeepsTheInstalledTips() async {
        let snapshots = model(
            FakeSnapshotSource(
                cached: "16.20", download: .success("16.21"), installedTips: Self.tips("viejo"),
                tipsDownload: .failure(.tipsInvalid)))

        await snapshots.run()

        #expect(snapshots.tips == Self.tips("viejo"))
        #expect(snapshots.status == .ready)
    }

    @Test func offlineTheInstalledTipsStillLoad() async {
        let failure = SnapshotDownloadError.manifestUnreachable("offline")
        let snapshots = model(
            FakeSnapshotSource(
                cached: nil, download: .failure(failure), installedTips: Self.tips("viejo"),
                tipsDownload: .failure(failure)))

        await snapshots.run()

        #expect(snapshots.tips == Self.tips("viejo"))
    }

    @Test func anUnreadableFileIsNotOpened() async {
        let snapshots = SnapshotModel(
            origin: .file(URL(filePath: "/nonexistent/emerald_plus.sqlite")))

        await snapshots.run()

        #expect(snapshots.meta == nil)
        #expect(snapshots.status == .failed(.unreadable(.unreadable)))
    }

    @Test func underXCTestNothingOpensOrDownloads() async throws {
        let suite = "MitoTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(SnapshotFixture.file.path, forKey: SnapshotModel.fileOverrideKey)

        let origin = SnapshotModel.Origin.live(underTest: true, defaults: defaults)
        let snapshots = SnapshotModel(origin: origin)
        await snapshots.run()

        guard case .none = origin else {
            Issue.record("Under XCTest the origin must be .none")
            return
        }
        #expect(snapshots.meta == nil)
        #expect(snapshots.status == .none)
        #expect(snapshots.tips == .empty)
    }

    #if DEBUG
        @Test func theDebugFileOverrideOpensTheGivenFile() async throws {
            let suite = "MitoTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(SnapshotFixture.file.path, forKey: SnapshotModel.fileOverrideKey)

            // Any other origin would download and write the real cache: never run it here.
            let origin = SnapshotModel.Origin.live(underTest: false, defaults: defaults)
            guard case .file(let url) = origin else {
                Issue.record("The override must open its file, not \(origin)")
                return
            }
            #expect(url == SnapshotFixture.file)
            let snapshots = SnapshotModel(origin: origin)
            await snapshots.run()

            #expect(snapshots.meta?.patch == Patch(rawValue: "16.21"))
            #expect(snapshots.meta?.bracket == .emeraldPlus)
            #expect(snapshots.status == .ready)
        }
    #endif
}
