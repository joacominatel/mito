import MitoAssets
import MitoCore

@testable import Mito

/// Upserts by (champion, role) like `PersonalDatabase`; only the override calls are real.
/// `MitoTestSupport` is not linkable from the app tests.
actor OverridesTestStore: PersonalStore {
    private var byKey: [String: ChampionOverride]
    private var failure: PersonalStoreError?

    init(overrides: [ChampionOverride] = [], failure: PersonalStoreError? = nil) {
        byKey = Dictionary(overrides.map { (Self.key($0.champion, $0.role), $0) }) { $1 }
        self.failure = failure
    }

    var stored: [ChampionOverride] {
        byKey.values.sorted { Self.key($0.champion, $0.role) < Self.key($1.champion, $1.role) }
    }

    func fail(with failure: PersonalStoreError?) { self.failure = failure }

    func overrides() throws(PersonalStoreError) -> [ChampionOverride] {
        if let failure { throw failure }
        return stored
    }

    func save(_ override: ChampionOverride) throws(PersonalStoreError) {
        if let failure { throw failure }
        byKey[Self.key(override.champion, override.role)] = override
    }

    func deleteOverride(champion: ChampionID, role: Role) throws(PersonalStoreError) {
        if let failure { throw failure }
        byKey[Self.key(champion, role)] = nil
    }

    func record(_ matches: [MyMatch]) {}
    func matches(_ query: MyMatchQuery) -> [MyMatch] { [] }
    func pool(for role: Role) -> [PoolEntry] { [] }
    func setPool(_ champions: [ChampionID], for role: Role) {}
    func appendImportLog(_ entry: ImportLogEntry) {}
    func importLog(limit: Int) -> [ImportLogEntry] { [] }
    func deleteAll() { byKey = [:] }

    private static func key(_ champion: ChampionID, _ role: Role) -> String {
        "\(champion.rawValue)-\(role.rawValue)"
    }
}

/// Two rune trees with small IDs, so a page reads at a glance; shard 91 and 93 sit in two rows
/// each, as real shards do (§16.2).
enum OverridesFixture {
    static let ahri = ChampionID(rawValue: 103)
    static let leeSin = ChampionID(rawValue: 64)
    static let aatrox = ChampionID(rawValue: 266)

    static let precision = PerkStyleID(rawValue: 1)
    static let domination = PerkStyleID(rawValue: 2)

    static let shards: [PerkStyle.Slot] = [
        .init(kind: .statMod, perks: ids(91, 92)),
        .init(kind: .statMod, perks: ids(91, 93)),
        .init(kind: .statMod, perks: ids(94, 93)),
    ]

    static func style(_ id: PerkStyleID, base: Int, shards: [PerkStyle.Slot] = shards)
        -> PerkStyle
    {
        PerkStyle(
            id: id, name: "Style \(id.rawValue)", iconPath: "",
            slots: [
                .init(kind: .keystone, perks: ids(base + 1, base + 2)),
                .init(kind: .regular, perks: ids(base + 3, base + 4)),
                .init(kind: .regular, perks: ids(base + 5, base + 6)),
                .init(kind: .regular, perks: ids(base + 7, base + 8)),
            ] + shards)
    }

    static let styles = [style(precision, base: 10), style(domination, base: 20)]

    /// Precision 11 + 13, 15, 17; Domination 23 (row 1) and 27 (row 3); shards 91, 93, 94.
    static let validPage = RunePage(
        primaryStyle: precision, subStyle: domination,
        perks: ids(11, 13, 15, 17, 23, 27, 91, 93, 94))

    static let gameData = GameData(
        champions: [(103, "Ahri"), (64, "Lee Sin"), (266, "Aatrox")].map {
            Champion(id: ChampionID(rawValue: $0), alias: $1, name: $1, iconPath: "")
        },
        items: [(1056, "Doran's Ring"), (1055, "Doran's Blade"), (2003, "Health Potion")].map {
            Item(id: ItemID(rawValue: $0), name: $1, totalGold: 400, iconPath: "", itemClass: nil)
        },
        perkStyles: styles,
        spells: [
            (4, "Flash", ["CLASSIC", "ARAM"]), (11, "Smite", ["CLASSIC"]),
            (32, "Mark", ["ARAM"]), (14, "Ignite", ["CLASSIC", "ARAM"]),
        ].map {
            SummonerSpell(
                id: SummonerSpellID(rawValue: $0), name: $1, iconPath: "", gameModes: Set($2))
        })

    static func ids(_ values: Int...) -> [PerkID] { values.map(PerkID.init) }

    /// The draft that builds `validPage` through the editor's own operations.
    static func validDraft() -> RunePageDraft {
        var draft = RunePageDraft()
        draft.setPrimaryStyle(precision, styles: styles)
        draft.keystone = PerkID(rawValue: 11)
        draft.primaryPerks = ids(13, 15, 17)
        draft.setSubStyle(domination)
        draft.setSecondaryPerk(PerkID(rawValue: 23), inRow: 0)
        draft.setSecondaryPerk(PerkID(rawValue: 27), inRow: 2)
        draft.shards = ids(91, 93, 94)
        return draft
    }
}
