import Foundation
import MitoCore

/// `manifest.json` as `MITO_CONTEXT.md` §14.12 describes it. Tips are listed there but are not
/// read here.
struct SnapshotManifest: Decodable, Equatable {
    struct Entry: Decodable, Equatable {
        let schemaVersion: Int
        let patch: String
        let queue: Int
        let bracket: String
        let url: URL
        let sha256: String
        let bytes: Int
        let rawBytes: Int
        let matches: Int
    }

    let currentPatch: Patch
    /// Entries that do not decode are dropped, so a future schema's shape cannot break this one.
    let snapshots: [Entry]

    private enum CodingKeys: String, CodingKey {
        case currentPatch, snapshots
    }

    private struct Lossy: Decodable {
        let entry: Entry?
        init(from decoder: any Decoder) throws { entry = try? Entry(from: decoder) }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let patch = try container.decode(String.self, forKey: .currentPatch)
        guard Self.isPatch(patch) else {
            throw DecodingError.dataCorruptedError(
                forKey: .currentPatch, in: container, debugDescription: "not an X.Y patch")
        }
        currentPatch = Patch(rawValue: patch)
        snapshots = try container.decode([Lossy].self, forKey: .snapshots).compactMap(\.entry)
    }

    static func decode(_ data: Data) throws(SnapshotDownloadError) -> SnapshotManifest {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(SnapshotManifest.self, from: data)
        } catch {
            throw .manifestInvalid
        }
    }

    /// The highest supported schema for the queue and bracket at `current_patch`.
    func entry(queue: QueueID, bracket: Bracket, supportedSchemaVersions: ClosedRange<Int>)
        -> Entry?
    {
        snapshots
            .filter {
                supportedSchemaVersions.contains($0.schemaVersion)
                    && $0.patch == currentPatch.rawValue && $0.queue == queue.rawValue
                    && $0.bracket == bracket.rawValue
            }
            .max { $0.schemaVersion < $1.schemaVersion }
    }

    /// The patch becomes a cache directory name, so nothing but `X.Y` gets through.
    static func isPatch(_ value: String) -> Bool {
        value.wholeMatch(of: #/[0-9]{1,3}\.[0-9]{1,3}/#) != nil
    }
}
