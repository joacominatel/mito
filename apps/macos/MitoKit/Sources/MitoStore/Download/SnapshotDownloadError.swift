/// One case per step of `SnapshotDownloader.installCurrent` and `installCurrentTips`. Every
/// failure leaves the previously installed file in place.
public enum SnapshotDownloadError: Error, Equatable, Sendable {
    /// The base URL or a manifest entry's URL is not `https`; nothing was sent.
    case insecureURL
    case manifestUnreachable(String)
    /// Not JSON in the `MITO_CONTEXT.md` §14.12 shape, or a `current_patch` that is not `X.Y`.
    case manifestInvalid
    /// No supported entry for the queue and bracket at the manifest's `current_patch`.
    case noMatchingSnapshot
    case downloadFailed(String)
    /// The compressed file is not the manifest's `bytes` long.
    case sizeMismatch(expected: Int, actual: Int)
    /// The compressed file's sha256 differs from the manifest's.
    case checksumMismatch
    /// Above the §14.12 hard limits (8 MB compressed, 32 MB uncompressed; 2 MB for tips).
    case sizeLimitExceeded
    case decompressionFailed
    /// The decompressed SQLite is not the manifest's `raw_bytes` long.
    case decompressedSizeMismatch(expected: Int, actual: Int)
    /// A verified tips file that is not the §14.12 shape, or not the entry's format and locale.
    case tipsInvalid
    case installFailed
}
