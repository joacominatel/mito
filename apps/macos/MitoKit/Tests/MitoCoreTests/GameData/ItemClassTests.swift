import MitoCore
import Testing

struct ItemClassTests {
    @Test(arguments: [
        ("starter", ItemClass.starter), ("consumable", .consumable), ("component", .component),
        ("boots_t1", .bootsT1), ("boots_t2", .bootsT2), ("legendary", .legendary),
        ("support_upgrade", .supportUpgrade),
    ])
    func mapsTheSnapshotClasses(raw: String, itemClass: ItemClass) {
        #expect(ItemClass(rawValue: raw) == itemClass)
        #expect(itemClass.rawValue == raw)
    }

    @Test func keepsAnUnknownClassVerbatim() {
        let itemClass = ItemClass(rawValue: "mythic")
        #expect(itemClass == .unknown("mythic"))
        #expect(itemClass.rawValue == "mythic")
    }
}
