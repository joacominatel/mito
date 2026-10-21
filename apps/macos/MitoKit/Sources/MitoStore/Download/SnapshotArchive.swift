import Compression
import CryptoKit
import Foundation

/// Verification and xz decoding of a downloaded `.sqlite.xz` (`MITO_CONTEXT.md` §14.12, §25).
enum SnapshotArchive {
    static let compressedSizeLimit = 8 * 1024 * 1024
    static let decompressedSizeLimit = 32 * 1024 * 1024

    private static let chunkSize = 64 * 1024

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { byte in
            let hex = String(byte, radix: 16)
            return byte < 0x10 ? "0" + hex : hex
        }.joined()
    }

    /// Checks `bytes` and `sha256` before anything decodes the file.
    static func verify(_ data: Data, bytes: Int, sha256: String) throws(SnapshotDownloadError) {
        guard data.count == bytes else {
            throw .sizeMismatch(expected: bytes, actual: data.count)
        }
        guard sha256Hex(data) == sha256.lowercased() else { throw .checksumMismatch }
    }

    /// Stops as soon as the output passes `limit`, so a hostile file cannot fill memory or disk.
    static func decompress(_ data: Data, limit: Int) throws(SnapshotDownloadError) -> Data {
        var remaining = data[...]
        var output = Data()
        do {
            let filter = try InputFilter(.decompress, using: .lzma) { (length: Int) -> Data? in
                guard !remaining.isEmpty else { return nil }
                let chunk = remaining.prefix(length)
                remaining = remaining.dropFirst(chunk.count)
                return Data(chunk)
            }
            while let chunk = try filter.readData(ofLength: chunkSize), !chunk.isEmpty {
                output.append(chunk)
                if output.count > limit { break }
            }
        } catch {
            throw .decompressionFailed
        }
        guard output.count <= limit else { throw .sizeLimitExceeded }
        return output
    }
}
