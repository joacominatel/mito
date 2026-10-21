import Foundation
import Testing

/// Copy lives in one catalog per feature (`Features/<X>/<X>.xcstrings`, `Shell.xcstrings`), so
/// parallel features never edit the same catalog. `Localizable.xcstrings` stays empty.
struct StringCatalogTests {
    @Test func localizableCatalogHasNoKeys() throws {
        let tree = try SourceTree()
        let catalog = tree.appRoot.appending(path: "Resources/Localizable.xcstrings")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: catalog))
        let strings = try #require((object as? [String: Any])?["strings"] as? [String: Any])

        #expect(
            strings.isEmpty,
            """
            Localizable.xcstrings holds \(strings.keys.sorted()). Use the feature's table: \
            Text("…", tableName: "<Feature>") or String(localized:table:).
            """)
    }

    /// Nested catalogs (`Features/Analysis/Matchup/Matchup.xcstrings`) flatten into one bundle
    /// directory, so a table name used twice would collide.
    @Test func everyCatalogNamesItsOwnTable() throws {
        let tree = try SourceTree()
        let enumerator = FileManager.default.enumerator(
            at: tree.appRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        let catalogs = (enumerator?.allObjects ?? []).compactMap { $0 as? URL }
            .filter { $0.pathExtension == "xcstrings" }
        let tables = Dictionary(grouping: catalogs) { $0.deletingPathExtension().lastPathComponent }

        #expect(catalogs.count > 1)
        let duplicated = tables.filter { $0.value.count > 1 }.keys.sorted()
        #expect(duplicated.isEmpty, "Catalogs share a table name: \(duplicated)")
    }
}
