import Foundation
import MitoCore

/// STOPGAP until P6-06: fixed loadouts for five champions, one per role, so the importer works
/// before the snapshot exists. IDs checked against CommunityDragon `latest` (16.20).
enum HandWrittenBuilds {
    struct Build {
        /// Used in the title when the client's static data has no name.
        let name: String
        let loadout: Loadout
    }

    /// Imports nothing: every champion without a build.
    static let fallback = Loadout(runes: nil, spells: nil, itemSet: nil, skillOrder: nil)

    static func loadout(for champion: ChampionID) -> Loadout {
        all[champion]?.loadout ?? fallback
    }

    static func name(of champion: ChampionID) -> String? {
        all[champion]?.name
    }

    static let all: [ChampionID: Build] = [
        // TOP
        ChampionID(rawValue: 122): Build(
            name: "Darius",
            loadout: loadout(
                runes: (
                    precision, resolve, [8010, 9111, 9105, 8299, 8444, 8242, 5008, 5008, 5011]
                ),
                spells: (flash, ghost),
                start: [1055, 2003], core: [6631, 3047, 3053],
                situational: [3742, 4401, 3065, 3075])
        ),
        // JUNGLE
        ChampionID(rawValue: 64): Build(
            name: "Lee Sin",
            loadout: loadout(
                runes: (
                    precision, domination, [8010, 9111, 9105, 8299, 8143, 8106, 5008, 5008, 5011]
                ),
                spells: (smite, flash),
                start: [1102, 2003], core: [6692, 3071, 3047],
                situational: [3053, 6333, 3156, 3026])
        ),
        // MIDDLE
        ChampionID(rawValue: 103): Build(
            name: "Ahri",
            loadout: loadout(
                runes: (
                    domination, sorcery, [8112, 8139, 8140, 8106, 8226, 8210, 5008, 5008, 5011]
                ),
                spells: (flash, ignite),
                start: [1056, 2003, 2003], core: [6655, 3020, 4645],
                situational: [3157, 3089, 3135, 3102])
        ),
        // BOTTOM
        ChampionID(rawValue: 222): Build(
            name: "Jinx",
            loadout: loadout(
                runes: (
                    precision, sorcery, [8008, 8009, 9104, 8017, 8233, 8236, 5005, 5008, 5011]
                ),
                spells: (flash, heal),
                start: [1055, 2003], core: [6672, 3006, 3031],
                situational: [3085, 3036, 3072, 3026])
        ),
        // UTILITY
        ChampionID(rawValue: 99): Build(
            name: "Lux",
            loadout: loadout(
                runes: (
                    sorcery, domination, [8229, 8226, 8210, 8237, 8139, 8106, 5008, 5008, 5011]
                ),
                spells: (flash, ignite),
                start: [3865, 2003, 2003], core: [3118, 3020, 4628],
                situational: [3157, 3089, 3041])
        ),
    ]

    private static let precision = 8000
    private static let domination = 8100
    private static let sorcery = 8200
    private static let resolve = 8400

    private static let ghost = 6
    private static let heal = 7
    private static let smite = 11
    private static let flash = 4
    private static let ignite = 14

    private static func loadout(
        runes: (primary: Int, sub: Int, perks: [Int]), spells: (Int, Int), start: [Int],
        core: [Int], situational: [Int]
    ) -> Loadout {
        Loadout(
            runes: RunePage(
                primaryStyle: PerkStyleID(rawValue: runes.primary),
                subStyle: PerkStyleID(rawValue: runes.sub),
                perks: runes.perks.map(PerkID.init(rawValue:))),
            spells: SpellPair(
                first: SummonerSpellID(rawValue: spells.0),
                second: SummonerSpellID(rawValue: spells.1)),
            itemSet: ItemSet(blocks: [
                block(String(localized: "Inicio", table: "Import"), start),
                block(String(localized: "Núcleo", table: "Import"), core),
                block(String(localized: "Situacionales", table: "Import"), situational),
            ]),
            skillOrder: nil)
    }

    /// A repeated ID becomes one entry with its count, in first-seen order.
    private static func block(_ title: String, _ ids: [Int]) -> ItemSet.Block {
        var order: [Int] = []
        var counts: [Int: Int] = [:]
        for id in ids {
            if counts[id] == nil { order.append(id) }
            counts[id, default: 0] += 1
        }
        return ItemSet.Block(
            title: title,
            items: order.map {
                ItemSet.Block.Item(id: ItemID(rawValue: $0), count: counts[$0] ?? 1)
            })
    }
}
