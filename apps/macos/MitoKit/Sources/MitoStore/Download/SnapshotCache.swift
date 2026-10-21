import Foundation
import MitoCore

/// `<root>/schema-<v>/<patch>/<queue>/<bracket>.sqlite`, plus a `<bracket>.json` record of the
/// manifest entry it came from. One file per (queue, bracket): the app keeps only the current
/// one (`MITO_CONTEXT.md` §14.13).
struct SnapshotCache {
    private struct Record: Codable {
        let schemaVersion: Int
        let patch: String
        let sha256: String
        let matches: Int
    }

    struct Hit {
        let snapshot: InstalledSnapshot
        let sha256: String
    }

    let root: URL

    private var fileManager: FileManager { .default }

    func fileURL(schemaVersion: Int, patch: String, queue: QueueID, bracket: Bracket) -> URL {
        directory(schemaVersion: schemaVersion, patch: patch, queue: queue)
            .appending(path: "\(bracket.rawValue).sqlite", directoryHint: .notDirectory)
    }

    /// The current file for the queue and bracket, if one was installed whole.
    func installed(queue: QueueID, bracket: Bracket, schemaVersions: ClosedRange<Int>) -> Hit? {
        candidates(queue: queue, bracket: bracket)
            .filter { schemaVersions.contains($0.schemaVersion) }
            .compactMap { hit(for: $0, queue: queue, bracket: bracket) }
            .max { lhs, rhs in
                let (left, right) = (lhs.snapshot, rhs.snapshot)
                guard left.schemaVersion == right.schemaVersion else {
                    return left.schemaVersion < right.schemaVersion
                }
                return left.patch.rawValue.compare(right.patch.rawValue, options: .numeric)
                    == .orderedAscending
            }
    }

    /// Both writes are atomic and the record goes last: a failure keeps the previous file and
    /// record, and a stale record only costs one extra download.
    func install(_ sqlite: Data, entry: SnapshotManifest.Entry, queue: QueueID, bracket: Bracket)
        throws(SnapshotDownloadError) -> InstalledSnapshot
    {
        let file = fileURL(
            schemaVersion: entry.schemaVersion, patch: entry.patch, queue: queue, bracket: bracket)
        let record = Record(
            schemaVersion: entry.schemaVersion, patch: entry.patch,
            sha256: entry.sha256.lowercased(),
            matches: entry.matches)
        do {
            try fileManager.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try sqlite.write(to: file, options: .atomic)
            try JSONEncoder().encode(record).write(to: Self.recordURL(for: file), options: .atomic)
        } catch {
            throw .installFailed
        }
        return InstalledSnapshot(
            schemaVersion: entry.schemaVersion, patch: Patch(rawValue: entry.patch), queue: queue,
            bracket: bracket, fileURL: file, matches: entry.matches)
    }

    /// Best effort: a leftover old file costs disk space, never correctness.
    func removeAll(queue: QueueID, bracket: Bracket, except kept: URL) {
        for candidate in candidates(queue: queue, bracket: bracket)
        where candidate.file.standardizedFileURL != kept.standardizedFileURL {
            try? fileManager.removeItem(at: candidate.file)
            try? fileManager.removeItem(at: Self.recordURL(for: candidate.file))
            removeEmptyDirectories(from: candidate.file.deletingLastPathComponent())
        }
    }

    private struct Candidate {
        let schemaVersion: Int
        let patch: String
        let file: URL
    }

    private func candidates(queue: QueueID, bracket: Bracket) -> [Candidate] {
        subdirectories(of: root).flatMap { schemaDirectory -> [Candidate] in
            let name = schemaDirectory.lastPathComponent
            guard name.hasPrefix("schema-"), let version = Int(name.dropFirst("schema-".count))
            else { return [] }
            return subdirectories(of: schemaDirectory).compactMap { patchDirectory in
                let patch = patchDirectory.lastPathComponent
                let file = fileURL(
                    schemaVersion: version, patch: patch, queue: queue, bracket: bracket)
                guard fileManager.fileExists(atPath: file.path) else { return nil }
                return Candidate(schemaVersion: version, patch: patch, file: file)
            }
        }
    }

    private func hit(for candidate: Candidate, queue: QueueID, bracket: Bracket) -> Hit? {
        guard let data = try? Data(contentsOf: Self.recordURL(for: candidate.file)),
            let record = try? JSONDecoder().decode(Record.self, from: data),
            record.schemaVersion == candidate.schemaVersion, record.patch == candidate.patch,
            SnapshotManifest.isPatch(record.patch)
        else { return nil }
        let snapshot = InstalledSnapshot(
            schemaVersion: record.schemaVersion, patch: Patch(rawValue: record.patch), queue: queue,
            bracket: bracket, fileURL: candidate.file, matches: record.matches)
        return Hit(snapshot: snapshot, sha256: record.sha256)
    }

    private func directory(schemaVersion: Int, patch: String, queue: QueueID) -> URL {
        root.appending(path: "schema-\(schemaVersion)", directoryHint: .isDirectory)
            .appending(path: patch, directoryHint: .isDirectory)
            .appending(path: String(queue.rawValue), directoryHint: .isDirectory)
    }

    private func subdirectories(of directory: URL) -> [URL] {
        let contents =
            (try? fileManager.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles])) ?? []
        return contents.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    }

    private func removeEmptyDirectories(from directory: URL) {
        var current = directory.standardizedFileURL
        let stop = root.standardizedFileURL.path
        while current.path.hasPrefix(stop + "/"),
            (try? fileManager.contentsOfDirectory(atPath: current.path).isEmpty) == true
        {
            try? fileManager.removeItem(at: current)
            current = current.deletingLastPathComponent()
        }
    }

    private static func recordURL(for file: URL) -> URL {
        file.deletingPathExtension().appendingPathExtension("json")
    }
}
