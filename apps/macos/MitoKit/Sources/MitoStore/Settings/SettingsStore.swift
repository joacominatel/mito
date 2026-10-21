public import Foundation
public import MitoCore
import os

/// `MitoSettings` as one JSON file in `<base>/<bundle id>/settings.json` (`MITO_CONTEXT.md` §21).
/// An actor so file I/O stays off the main actor and saves never interleave.
public actor SettingsStore {
    public static let fallbackBundleIdentifier = "com.joacominatel.mito"

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? fallbackBundleIdentifier, category: "MitoStore")

    public nonisolated let fileURL: URL

    public init(
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        baseDirectory: URL = .applicationSupportDirectory
    ) {
        fileURL =
            baseDirectory
            .appending(
                path: bundleIdentifier ?? Self.fallbackBundleIdentifier, directoryHint: .isDirectory
            )
            .appending(path: "settings.json", directoryHint: .notDirectory)
    }

    /// Never fails: a missing file gives the defaults, and a corrupt one is moved aside first.
    public func load() -> MitoSettings {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch CocoaError.fileReadNoSuchFile {
            return MitoSettings()
        } catch {
            Self.logger.error(
                "Settings unreadable: \(error.localizedDescription, privacy: .private)")
            moveAside()
            return MitoSettings()
        }

        do {
            return try JSONDecoder().decode(MitoSettings.self, from: data)
        } catch {
            Self.logger.error("Settings file is not valid settings JSON")
            moveAside()
            return MitoSettings()
        }
    }

    public func save(_ settings: MitoSettings) throws(StoreError) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(settings).write(to: fileURL, options: .atomic)
        } catch {
            Self.logger.error(
                "Settings not saved: \(error.localizedDescription, privacy: .private)")
            throw .settingsNotSaved
        }
    }

    private func moveAside() {
        let stamp = Date.now.formatted(
            .iso8601.year().month().day().dateSeparator(.omitted)
                .time(includingFractionalSeconds: true).timeSeparator(.omitted)
                .timeZone(separator: .omitted))
        let destination = fileURL.deletingLastPathComponent()
            .appending(path: "settings.corrupt-\(stamp).json", directoryHint: .notDirectory)
        do {
            try FileManager.default.moveItem(at: fileURL, to: destination)
            Self.logger.notice(
                "Moved unusable settings aside to \(destination.lastPathComponent, privacy: .public)"
            )
        } catch {
            Self.logger.error(
                "Could not move unusable settings aside: \(error.localizedDescription, privacy: .private)"
            )
        }
    }
}
