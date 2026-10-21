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
}
