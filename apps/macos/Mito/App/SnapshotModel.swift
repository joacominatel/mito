import Foundation
import MitoCore
import MitoStore
import Observation
import os

/// `SnapshotDownloader` in the app; a fake in tests.
nonisolated protocol SnapshotSource: Sendable {
    /// Reads only the disk.
    func cachedFile() async -> URL?
    /// On failure the cached file stays where it was.
    func downloadCurrent() async throws(SnapshotDownloadError) -> URL
    /// Reads only the disk; `.empty` when none is installed.
    func installedTips() async -> CuratedTips
    /// On failure the installed tips stay where they were.
    func downloadCurrentTips() async throws(SnapshotDownloadError) -> CuratedTips
}

/// Ranked Solo/Duo at Emerald+, the only snapshot the app reads today (§14.8), and the tips in
/// the UI's language.
nonisolated struct DownloadedSnapshots: SnapshotSource {
    /// The UI's only language today (§14.12).
    static let tipsLocale = "es-AR"

    let downloader: SnapshotDownloader

    func cachedFile() async -> URL? {
        await downloader.installedSnapshot(
            queue: QueueType.rankedSolo.queueID, bracket: .emeraldPlus)?
            .fileURL
    }

    func downloadCurrent() async throws(SnapshotDownloadError) -> URL {
        try await downloader.installCurrent(
            queue: QueueType.rankedSolo.queueID, bracket: .emeraldPlus
        ).fileURL
    }

    func installedTips() async -> CuratedTips {
        await downloader.installedTips(locale: Self.tipsLocale)
    }

    func downloadCurrentTips() async throws(SnapshotDownloadError) -> CuratedTips {
        try await downloader.installCurrentTips(locale: Self.tipsLocale)
    }
}

/// The open per-patch snapshot every feature reads its stats from (§9.3, §20.3), and the curated
/// tips the Matchup tab reads (§14.12).
@Observable
final class SnapshotModel {
    enum Status: Equatable {
        case none
        case downloading
        case ready
        case failed(Failure)
    }

    enum Failure: Equatable {
        case download(SnapshotDownloadError)
        case unreadable(SnapshotReadError)
    }

    enum Origin {
        /// Previews and tests: nothing opens.
        case none
        /// Debug `-MitoSnapshotFile`: this file, never a download.
        case file(URL)
        /// The cached file first, then the current patch's download.
        case source(any SnapshotSource)
    }

    typealias Opener = @Sendable (URL) throws(SnapshotReadError) -> any StatsProvider

    static let fileOverrideKey = "MitoSnapshotFile"

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? SettingsStore.fallbackBundleIdentifier,
        category: "App")

    /// Empty until a snapshot opens; a failed download keeps the last one opened.
    private(set) var provider: any StatsProvider = NoSnapshot()
    /// The last open or download attempt.
    private(set) var status: Status = .none
    /// The installed ones until a download replaces them; a failed one keeps them.
    private(set) var tips: CuratedTips = .empty

    @ObservationIgnored private let origin: Origin
    @ObservationIgnored private let opener: Opener

    init(
        origin: Origin = .none,
        open: @escaping Opener = { url throws(SnapshotReadError) in
            try SnapshotReader(fileURL: url)
        }
    ) {
        self.origin = origin
        opener = open
    }

    /// The open file's identity; `nil` in the degraded mode of §20.3.
    var meta: SnapshotMeta? { provider.meta }

    func run() async {
        switch origin {
        case .none:
            return
        case .file(let url):
            await open(url)
        case .source(let source):
            if let cached = await source.cachedFile() { await open(cached) }
            tips = await source.installedTips()
            status = .downloading
            do {
                await open(try await source.downloadCurrent())
            } catch {
                // Offline is normal: quiet, the cached file stays in use.
                Self.logger.notice(
                    "Snapshot download failed: \(String(describing: error), privacy: .public)")
                status = .failed(.download(error))
            }
            do {
                tips = try await source.downloadCurrentTips()
            } catch {
                Self.logger.notice(
                    "Tips download failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func open(_ url: URL) async {
        do {
            provider = try await Self.read(url, with: opener)
            status = .ready
        } catch {
            status = .failed(.unreadable(error))
        }
    }

    /// The reader loads the whole file synchronously.
    @concurrent
    private static func read(_ url: URL, with open: Opener) async throws(SnapshotReadError)
        -> any StatsProvider
    {
        try open(url)
    }

    private struct NoSnapshot: StatsProvider {
        func roleGames(for champion: ChampionID) -> [Role: Int] { [:] }
    }
}

extension SnapshotModel.Origin {
    /// Info.plist key filled from `MITO_DATA_BASE_URL` in the xcconfigs (ADR 0011).
    static let baseURLKey = "MitoDataBaseURL"

    /// Under XCTest nothing opens, so tests never download or touch the real cache.
    static func live(
        underTest: Bool, defaults: UserDefaults = .standard,
        info: [String: Any]? = Bundle.main.infoDictionary
    ) -> Self {
        if underTest { return .none }
        #if DEBUG
            if let path = defaults.string(forKey: SnapshotModel.fileOverrideKey) {
                return .file(URL(filePath: path))
            }
        #endif
        guard let base = dataBaseURL(info: info),
            let downloader = try? SnapshotDownloader(baseURL: base)
        else { return .none }
        return .source(DownloadedSnapshots(downloader: downloader))
    }

    /// `nil` when missing, not HTTPS, or on an `.invalid` host: the app then never downloads.
    static func dataBaseURL(info: [String: Any]?) -> String? {
        guard let value = info?[baseURLKey] as? String,
            let url = URL(string: value), url.scheme?.lowercased() == "https",
            let host = url.host()?.lowercased(), !host.isEmpty,
            host != "invalid", !host.hasSuffix(".invalid")
        else { return nil }
        return value
    }
}
