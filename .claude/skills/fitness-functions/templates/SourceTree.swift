// SourceTree.swift — shared by the source-scan fitness functions.
//
// Lives in any MitoKit test target (Tests/<X>Tests/). Resolves the package
// root by walking up from #filePath to the nearest Package.swift, so it works
// from any checkout and any nesting depth: Tests/<X>Tests/ → ../../Sources/<X>/.

import Foundation

struct SourceTree {
    enum Failure: Error, CustomStringConvertible {
        case packageRootNotFound(String)
        case missingDirectory(String)

        var description: String {
            switch self {
            case .packageRootNotFound(let path): "no Package.swift above \(path)"
            case .missingDirectory(let path): "expected a source directory at \(path)"
            }
        }
    }

    let packageRoot: URL

    init(filePath: String = #filePath) throws {
        var directory = URL(filePath: filePath).deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: directory.appending(path: "Package.swift").path) {
            let parent = directory.deletingLastPathComponent()
            guard parent.path != directory.path else { throw Failure.packageRootNotFound(filePath) }
            directory = parent
        }
        packageRoot = directory
    }

    var sourcesRoot: URL { packageRoot.appending(path: "Sources", directoryHint: .isDirectory) }

    // ADAPT if the app target moves: apps/macos/Mito sits next to apps/macos/MitoKit.
    var appRoot: URL { packageRoot.deletingLastPathComponent().appending(path: "Mito", directoryHint: .isDirectory) }

    func targetNames() throws -> [String] {
        try FileManager.default
            .contentsOfDirectory(at: sourcesRoot, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map(\.lastPathComponent)
            .sorted()
    }

    func target(_ name: String) -> URL { sourcesRoot.appending(path: name, directoryHint: .isDirectory) }

    /// Every shipped tree: each MitoKit target plus the app target.
    func shippedRoots() throws -> [URL] {
        try targetNames().map(target) + [appRoot]
    }

    func swiftFiles(in root: URL) throws -> [SourceFile] {
        guard FileManager.default.fileExists(atPath: root.path) else { throw Failure.missingDirectory(root.path) }
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        return try (enumerator?.allObjects ?? [])
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .map { try SourceFile(url: $0, relativeTo: packageRoot.deletingLastPathComponent()) }
    }
}

struct SourceFile {
    let path: String
    /// Source with full-line and block comments blanked; strings are kept, so
    /// interpolations stay visible. A trailing `// …` comment still counts —
    /// reword it rather than teaching the scanner Swift's grammar.
    let code: String

    init(url: URL, relativeTo base: URL) throws {
        path = String(url.path.dropFirst(base.path.count + 1))
        var inBlock = false
        code = try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> Substring in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if inBlock {
                    if trimmed.contains("*/") { inBlock = false }
                    return ""
                }
                if trimmed.hasPrefix("/*") {
                    inBlock = !trimmed.contains("*/")
                    return ""
                }
                return trimmed.hasPrefix("//") ? "" : line
            }
            .joined(separator: "\n")
    }

    var lines: [Substring] { code.split(separator: "\n", omittingEmptySubsequences: false) }

    /// Modules named by `import` declarations, including `@testable`,
    /// `@preconcurrency`, access-level (`public import`) and kind (`import struct`) forms.
    var importedModules: Set<String> {
        let declaration = #/^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:public|package|internal|fileprivate|private)\s+)?import\s+(?:(?:typealias|struct|class|enum|protocol|let|var|func)\s+)?(\w+)/#
        return Set(lines.compactMap { line in (try? declaration.prefixMatch(in: line)).map { String($0.1) } })
    }
}
