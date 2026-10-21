public import Foundation
import os

extension SnapshotDownloader {
    /// `<caches>/<bundle id>/tips`, beside `cacheDirectory`.
    public nonisolated var tipsDirectory: URL {
        cacheDirectory.deletingLastPathComponent()
            .appending(path: "tips", directoryHint: .isDirectory)
    }

    private nonisolated var tipsCache: TipsCache { TipsCache(root: tipsDirectory) }

    /// Reads only the disk; `.empty` when nothing usable is installed for the locale.
    public func installedTips(locale: String) -> CuratedTips {
        tipsCache.data(locale: locale).flatMap { CuratedTips.decode($0, locale: locale) } ?? .empty
    }

    /// Downloads only when the manifest's sha256 differs from the installed file's. With no
    /// supported entry for the locale there are no tips: the installed file is removed and the
    /// result is `.empty`. On any error the installed file stays where it was.
    public func installCurrentTips(locale: String) async throws(SnapshotDownloadError)
        -> CuratedTips
    {
        let manifest = try await currentManifest()
        guard
            let entry = manifest.tipsEntry(
                locale: locale, supportedFormatVersions: CuratedTips.supportedFormatVersions)
        else {
            tipsCache.remove(locale: locale)
            return .empty
        }

        if let installed = tipsCache.data(locale: locale),
            SnapshotArchive.sha256Hex(installed) == entry.sha256.lowercased(),
            let tips = CuratedTips.decode(installed, locale: locale)
        {
            Self.logger.debug("Tips \(locale, privacy: .public) already current")
            return tips
        }

        guard Self.isHTTPS(entry.url) else { throw .insecureURL }
        guard entry.bytes <= CuratedTips.sizeLimit else { throw .sizeLimitExceeded }

        let data: Data
        do {
            data = try await fetch(entry.url, limit: entry.bytes)
        } catch .tooLarge(let received) {
            throw .sizeMismatch(expected: entry.bytes, actual: received)
        } catch {
            throw .downloadFailed(error.description)
        }
        try SnapshotArchive.verify(data, bytes: entry.bytes, sha256: entry.sha256)
        guard let tips = CuratedTips.decode(data, locale: locale) else { throw .tipsInvalid }

        try tipsCache.install(data, locale: locale)
        Self.logger.notice(
            "Installed \(tips.records.count, privacy: .public) tips for \(locale, privacy: .public)"
        )
        return tips
    }
}
