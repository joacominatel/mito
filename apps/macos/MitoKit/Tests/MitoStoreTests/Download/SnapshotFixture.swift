import Foundation
import MitoTestSupport

@testable import MitoStore

/// The committed mito-data `fixtures/snapshot/` files, read in place so they cannot drift from
/// the contract fixture. An unreadable file is empty data, which fails every test that uses it.
enum SnapshotFixture {
    static let manifest = read("snapshot/manifest.json")

    /// `emerald_plus.sqlite.xz`: Python `lzma` defaults (single stream, LZMA2, CRC64).
    static let compressed = read("snapshot/emerald_plus.sqlite.xz")

    /// `tips/es-AR.json`, listed in the manifest's `tips`.
    static let tips = read("snapshot/tips/es-AR.json")

    /// `emerald_plus.sqlite`, the decompressed file, by digest and size.
    static let sqliteSHA256 = SnapshotArchive.sha256Hex(sqlite)
    static let sqliteBytes = sqlite.count

    private static let sqlite = read("snapshot/emerald_plus.sqlite")

    private static func read(_ path: String) -> Data {
        (try? Data(contentsOf: Fixtures.url(path))) ?? Data()
    }
}
