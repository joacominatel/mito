import Foundation
import MitoCore

/// `manifest.json` as `MITO_CONTEXT.md` §14.12 describes it.
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

    struct TipsEntry: Decodable, Equatable {
        let formatVersion: Int
        let locale: String
        let url: URL
        let sha256: String
        let bytes: Int
        let updatedAt: String?
    }

    let currentPatch: Patch
    /// Entries that do not decode are dropped, so a future schema's shape cannot break this one.
    let snapshots: [Entry]
    /// Same rule as `snapshots`; a manifest without the key has no tips.
    let tips: [TipsEntry]

    private enum CodingKeys: String, CodingKey {
        case currentPatch, snapshots, tips
    }

    private struct Lossy<Element: Decodable>: Decodable {
        let entry: Element?
        init(from decoder: any Decoder) throws { entry = try? Element(from: decoder) }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let patch = try container.decode(String.self, forKey: .currentPatch)
        guard Self.isPatch(patch) else {
            throw DecodingError.dataCorruptedError(
                forKey: .currentPatch, in: container, debugDescription: "not an X.Y patch")
        }
        currentPatch = Patch(rawValue: patch)
        snapshots = try container.decode([Lossy<Entry>].self, forKey: .snapshots)
            .compactMap(\.entry)
        tips =
            (try? container.decodeIfPresent([Lossy<TipsEntry>].self, forKey: .tips))?
            .compactMap(\.entry) ?? []
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

    /// The highest supported format for the locale; tips are not tied to `current_patch`.
    func tipsEntry(locale: String, supportedFormatVersions: ClosedRange<Int>) -> TipsEntry? {
        tips
            .filter {
                supportedFormatVersions.contains($0.formatVersion) && $0.locale == locale
            }
            .max { $0.formatVersion < $1.formatVersion }
    }

    /// The patch becomes a cache directory name, so nothing but `X.Y` gets through.
    static func isPatch(_ value: String) -> Bool {
        value.wholeMatch(of: #/[0-9]{1,3}\.[0-9]{1,3}/#) != nil
    }
}
