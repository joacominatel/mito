#if DEBUG
    import MitoAssets
    import MitoCore
    import SwiftUI

    extension OverridesModel {
        /// Two stored overrides, one with a fixed page.
        static var preview: OverridesModel {
            OverridesModel(
                store: PreviewOverridesStore(overrides: [.previewFixedPage, .previewFavorite]))
        }
    }

    extension ChampionOverride {
        static let previewFixedPage = ChampionOverride(
            champion: ChampionID(rawValue: 103), role: .middle, runeMode: .fixed,
            fixedPage: RunePage(
                primaryStyle: PerkStyleID(rawValue: 8100), subStyle: PerkStyleID(rawValue: 8200),
                perks: [8112, 8139, 8138, 8135, 8226, 8210, 5008, 5008, 5001].map(PerkID.init)),
            spellMode: .fixed,
            fixedSpells: SpellPair(
                first: SummonerSpellID(rawValue: 4), second: SummonerSpellID(rawValue: 14)),
            itemMode: .fixedSet,
            fixedItems: ItemSet(blocks: [
                ItemSet.Block(
                    title: "Inicio",
                    items: [
                        ItemSet.Block.Item(id: ItemID(rawValue: 1056)),
                        ItemSet.Block.Item(id: ItemID(rawValue: 2003), count: 2),
                    ])
            ]),
            isFavorite: true)

        static let previewFavorite = ChampionOverride(
            champion: ChampionID(rawValue: 64), role: .jungle, itemMode: .skip,
            isExcludedFromPool: true)
    }

    extension GameData {
        /// Domination and Sorcery with real IDs, a few CLASSIC spells, and starter items.
        static let overridesPreview: GameData = {
            let shards: [PerkStyle.Slot] = [
                .init(kind: .statMod, perks: [5008, 5005, 5007].map(PerkID.init)),
                .init(kind: .statMod, perks: [5008, 5010, 5001].map(PerkID.init)),
                .init(kind: .statMod, perks: [5011, 5013, 5001].map(PerkID.init)),
            ]
            func style(_ id: Int, _ name: String, _ rows: [[Int]]) -> PerkStyle {
                PerkStyle(
                    id: PerkStyleID(rawValue: id), name: name, iconPath: "",
                    slots: [.init(kind: .keystone, perks: rows[0].map(PerkID.init))]
                        + rows.dropFirst().map { .init(kind: .regular, perks: $0.map(PerkID.init)) }
                        + shards)
            }
            let perks: [(Int, String)] = [
                (8112, "Electrocutar"), (8128, "Cosecha oscura"), (9923, "Lluvia de cuchillas"),
                (8126, "Golpe bajo"), (8139, "Sabor a sangre"), (8143, "Impacto repentino"),
                (8136, "Poro zombi"), (8120, "Poro fantasmal"),
                (8138, "Colección de globos oculares"),
                (8135, "Cazador tesorero"), (8105, "Cazador incansable"), (8106, "Cazador supremo"),
                (8214, "Invocar a Aery"), (8229, "Cometa arcano"), (8230, "Ímpetu creciente"),
                (8224, "Orbe anulador"), (8226, "Banda de maná"), (8275, "Capa de nimbo"),
                (8210, "Trascendencia"), (8234, "Celeridad"), (8233, "Sobrecarga absoluta"),
                (8237, "Abrasar"), (8232, "Caminar sobre el agua"), (8236, "Tormenta acumulada"),
                (5008, "Fuerza adaptable"), (5005, "Velocidad de ataque"), (5007, "Aceleración"),
                (5010, "Velocidad de movimiento"), (5001, "Vida escalable"), (5011, "Vida"),
                (5013, "Tenacidad y resistencia a la ralentización"),
            ]
            return GameData(
                champions: [(103, "Ahri"), (64, "Lee Sin"), (238, "Zed"), (86, "Garen")].map {
                    Champion(id: ChampionID(rawValue: $0), alias: $1, name: $1, iconPath: "")
                },
                items: [
                    (1056, "Anillo de Doran", 400), (2003, "Poción de vida", 50),
                    (3020, "Botas del hechicero", 1100),
                ]
                .map {
                    Item(
                        id: ItemID(rawValue: $0), name: $1, totalGold: $2, iconPath: "",
                        itemClass: nil)
                },
                perkStyles: [
                    style(
                        8100, "Dominación",
                        [
                            [8112, 8128, 9923], [8126, 8139, 8143], [8136, 8120, 8138],
                            [8135, 8105, 8106],
                        ]),
                    style(
                        8200, "Brujería",
                        [
                            [8214, 8229, 8230], [8224, 8226, 8275], [8210, 8234, 8233],
                            [8237, 8232, 8236],
                        ]),
                ],
                perks: perks.map { Perk(id: PerkID(rawValue: $0), name: $1, iconPath: "") },
                spells: [
                    (4, "Destello", ["CLASSIC", "ARAM"]), (14, "Prender", ["CLASSIC", "ARAM"]),
                    (11, "Aplastar", ["CLASSIC"]), (32, "Marca", ["ARAM"]),
                ]
                .map {
                    SummonerSpell(
                        id: SummonerSpellID(rawValue: $0), name: $1, iconPath: "",
                        gameModes: Set($2))
                })
        }()
    }

    /// Overrides only, kept in memory for previews.
    private actor PreviewOverridesStore: PersonalStore {
        private var stored: [ChampionOverride]

        init(overrides: [ChampionOverride]) { stored = overrides }

        func record(_ matches: [MyMatch]) {}
        func matches(_ query: MyMatchQuery) -> [MyMatch] { [] }
        func pool(for role: Role) -> [PoolEntry] { [] }
        func setPool(_ champions: [ChampionID], for role: Role) {}
        func overrides() -> [ChampionOverride] { stored }
        func save(_ override: ChampionOverride) {
            stored.removeAll { $0.champion == override.champion && $0.role == override.role }
            stored.append(override)
        }
        func deleteOverride(champion: ChampionID, role: Role) {
            stored.removeAll { $0.champion == champion && $0.role == role }
        }
        func appendImportLog(_ entry: ImportLogEntry) {}
        func importLog(limit: Int) -> [ImportLogEntry] { [] }
        func deleteAll() { stored = [] }
    }

    #Preview("Editor con página fija") {
        let model = OverridesModel()
        model.draft = OverrideDraft(.previewFixedPage, styles: GameData.overridesPreview.perkStyles)
        return OverrideEditor(model: model, gameData: .overridesPreview)
    }
#endif
