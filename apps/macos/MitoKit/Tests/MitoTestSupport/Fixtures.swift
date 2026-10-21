public import Foundation

/// The repo-root `fixtures/` tree, shared with the Python tools; read in place, never bundled.
public enum Fixtures {
    public static let root: URL = URL(filePath: #filePath)
        .deletingLastPathComponent()  // Tests/MitoTestSupport/
        .deletingLastPathComponent()  // Tests/
        .deletingLastPathComponent()  // MitoKit/
        .deletingLastPathComponent()  // macos/
        .deletingLastPathComponent()  // apps/
        .deletingLastPathComponent()  // repository root
        .appending(path: "fixtures", directoryHint: .isDirectory)

    /// `Fixtures.url("lcu/cases/champ-select/blind.json")`.
    public static func url(_ relativePath: String) -> URL {
        root.appending(path: relativePath)
    }
}
