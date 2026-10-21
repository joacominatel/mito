import MitoAssets
import MitoCore
import Testing

struct GameDataTests {
    private static let ahri = Champion(
        id: ChampionID(rawValue: 103), alias: "Ahri", name: "Ahri", iconPath: "/a.png")
    private static let domination = PerkStyle(
        id: PerkStyleID(rawValue: 8100), name: "Domination", iconPath: "/d.png",
        slots: [.init(kind: .keystone, perks: [PerkID(rawValue: 8112)])])
    private static let sorcery = PerkStyle(
        id: PerkStyleID(rawValue: 8200), name: "Sorcery", iconPath: "/s.png", slots: [])

    @Test func eachLookupFindsItsEntryByID() {
        let item = Item(
            id: ItemID(rawValue: 3157), name: "Zhonya's", totalGold: 3250, iconPath: "/z.png",
            itemClass: nil)
        let perk = Perk(id: PerkID(rawValue: 8112), name: "Electrocute", iconPath: "/e.png")
        let spell = SummonerSpell(
            id: SummonerSpellID(rawValue: 4), name: "Flash", iconPath: "/f.png",
            gameModes: ["CLASSIC"])
        let data = GameData(
            champions: [Self.ahri], items: [item], perkStyles: [Self.domination], perks: [perk],
            spells: [spell])

        #expect(data.champion(Self.ahri.id) == Self.ahri)
        #expect(data.item(item.id) == item)
        #expect(data.perk(perk.id) == perk)
        #expect(data.perkStyle(Self.domination.id) == Self.domination)
        #expect(data.spell(spell.id) == spell)
    }

    @Test func anUnknownIDFindsNothing() {
        let data = GameData(champions: [Self.ahri])
        #expect(data.champion(ChampionID(rawValue: 1)) == nil)
        #expect(data.item(ItemID(rawValue: 103)) == nil)
        #expect(data.perk(PerkID(rawValue: 103)) == nil)
        #expect(data.perkStyle(PerkStyleID(rawValue: 103)) == nil)
        #expect(data.spell(SummonerSpellID(rawValue: 103)) == nil)
    }

    @Test func perkStylesKeepTheirOrder() {
        let data = GameData(perkStyles: [Self.sorcery, Self.domination])
        #expect(data.perkStyles == [Self.sorcery, Self.domination])
    }

    @Test func theFirstEntryWinsWhenAnIDRepeats() {
        let duplicate = Champion(id: Self.ahri.id, alias: "Other", name: "Other", iconPath: "")
        #expect(GameData(champions: [Self.ahri, duplicate]).champion(Self.ahri.id) == Self.ahri)
    }

    @Test func theListsKeepClientOrderWithOneEntryPerID() {
        let zed = Champion(id: ChampionID(rawValue: 238), alias: "Zed", name: "Zed", iconPath: "")
        let duplicate = Champion(id: Self.ahri.id, alias: "Other", name: "Other", iconPath: "")
        let flash = SummonerSpell(
            id: SummonerSpellID(rawValue: 4), name: "Flash", iconPath: "", gameModes: ["CLASSIC"])
        let boots = Item(
            id: ItemID(rawValue: 1001), name: "Boots", totalGold: 300, iconPath: "", itemClass: nil)
        let data = GameData(
            champions: [zed, Self.ahri, duplicate], items: [boots], spells: [flash])

        #expect(data.allChampions == [zed, Self.ahri])
        #expect(data.allItems == [boots])
        #expect(data.allSpells == [flash])
    }
}
