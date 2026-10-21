/// Why `SnapshotReader` could not open a snapshot; any of them means no provider (§20.3).
public enum SnapshotReadError: Error, Equatable, Sendable {
    /// Missing, not an SQLite file, or no readable `meta` table.
    case unreadable
    case unsupportedSchemaVersion(Int)
    case missingMetaKey(String)
    /// The key is present but its value does not parse in the §17 shape.
    case invalidMetaValue(String)
    /// A table the reader needs is missing, has a missing column, or holds a value outside §17.
    case malformedTable(String)
}
