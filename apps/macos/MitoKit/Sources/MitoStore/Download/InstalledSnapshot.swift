public import Foundation
public import MitoCore

/// The decompressed snapshot on disk, ready for the reader to open.
public struct InstalledSnapshot: Equatable, Sendable {
    public let schemaVersion: Int
    public let patch: Patch
    public let queue: QueueID
    public let bracket: Bracket
    public let fileURL: URL
    /// The manifest's `matches` for this file.
    public let matches: Int
}
