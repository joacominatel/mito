// ImportBoundaryTests.swift — fitness function, Pattern 1 (import fence + API-surface scan).
//
// Rules (MITO_CONTEXT.md §7, .claude/rules/macos.md):
//  - MitoEngine is pure: it imports only MitoCore and Foundation.
//  - URLSession appears only in LCUKit and MitoStore. Foundation alone reaches
//    URLSession, so the fence is on the API, not on an import.
// Needs SourceTree.swift in the same test target.

import Foundation
import Testing

struct ImportBoundaryTests {
    // The fence, not a headcount: widening either set is a documented decision.
    private static let engineImports: Set<String> = ["MitoCore", "Foundation"]
    private static let networkingTargets: Set<String> = ["LCUKit", "MitoStore"]

    @Test func mitoEngineImportsOnlyMitoCoreAndFoundation() throws {
        let tree = try SourceTree()
        let files = try tree.swiftFiles(in: tree.target("MitoEngine"))
        #expect(!files.isEmpty, "no sources under \(tree.target("MitoEngine").path)")

        for file in files {
            let extra = file.importedModules.subtracting(Self.engineImports)
            if !extra.isEmpty {
                Issue.record("\(file.path) imports \(extra.sorted()); MitoEngine stays pure (MITO_CONTEXT.md §7). Move the dependency out, or record why the fence widens.")
            }
        }
    }

    @Test func urlSessionIsUsedOnlyInLCUKitAndMitoStore() throws {
        let tree = try SourceTree()
        let roots = try tree.targetNames()
            .filter { !Self.networkingTargets.contains($0) }
            .map(tree.target) + [tree.appRoot]
        let needle = #/\bURLSession/#

        for root in roots {
            for file in try tree.swiftFiles(in: root) {
                for (index, line) in file.lines.enumerated() where line.contains(needle) {
                    Issue.record("\(file.path):\(index + 1) uses URLSession outside \(Self.networkingTargets.sorted()) — go through LCUClient or the store.")
                }
            }
        }
    }
}
