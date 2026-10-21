import Foundation
import Testing

/// The module graph of `MITO_CONTEXT.md` §9.2 and `.claude/rules/macos.md`, as an import fence.
struct ImportBoundaryTests {
    /// A fence, not a headcount: widening an entry is a documented decision. Each module gets
    /// Foundation and its Package.swift dependencies; the extras are the planned system ones
    /// (`os` for logging, `Synchronization` for `Mutex`, `Security` for the LCU trust check,
    /// GRDB for the store). Nothing may import the app target.
    private static let allowedImports: [String: Set<String>] = [
        "MitoCore": ["Foundation"],
        "LCUKit": ["Foundation", "MitoCore", "os", "Security", "Synchronization"],
        "MitoStore": ["Foundation", "MitoCore", "os", "Synchronization", "GRDB"],
        "MitoEngine": ["Foundation", "MitoCore"],
        "MitoAssets": ["Foundation", "MitoCore", "LCUKit", "os", "Synchronization"],
        "MitoImport": ["Foundation", "MitoCore", "LCUKit"],
        "MitoTestSupport": ["Foundation", "MitoCore", "LCUKit", "Synchronization"],
    ]
    private static let networkingTargets: Set<String> = ["LCUKit", "MitoStore"]

    @Test func everyTargetHasAnImportAllowlist() throws {
        let tree = try SourceTree()
        let unfenced = Set(try tree.targetNames()).subtracting(Self.allowedImports.keys)
        #expect(
            unfenced.isEmpty,
            """
            \(unfenced.sorted()) have no entry in ImportBoundaryTests.allowedImports. Add one \
            matching the target's Package.swift dependencies and MITO_CONTEXT.md §9.2.
            """)
    }

    @Test(arguments: allowedImports.keys.sorted())
    func moduleImportsOnlyItsAllowlist(_ module: String) throws {
        let tree = try SourceTree()
        let root = module == "MitoTestSupport" ? tree.testSupportRoot : tree.target(module)
        let files = try tree.swiftFiles(in: root)
        #expect(!files.isEmpty, "no sources under \(root.path)")
        let allowed = Self.allowedImports[module] ?? []

        for file in files {
            let extra = file.importedModules.subtracting(allowed)
            if !extra.isEmpty {
                Issue.record(
                    """
                    \(file.path) imports \(extra.sorted()); \(module) may import only \
                    \(allowed.sorted()) (MITO_CONTEXT.md §9.2). Move the dependency out, or \
                    record why the fence widens.
                    """)
            }
        }
    }

    @Test func urlSessionIsUsedOnlyInLCUKitAndMitoStore() throws {
        let tree = try SourceTree()
        let roots =
            try tree.targetNames()
            .filter { !Self.networkingTargets.contains($0) }
            .map(tree.target) + [tree.appRoot]
        let needle = #/\bURLSession/#

        for root in roots {
            for file in try tree.swiftFiles(in: root) {
                for (index, line) in file.lines.enumerated() where line.contains(needle) {
                    Issue.record(
                        """
                        \(file.path):\(index + 1) uses URLSession outside \
                        \(Self.networkingTargets.sorted()) — go through LCUClient or the store.
                        """)
                }
            }
        }
    }
}
