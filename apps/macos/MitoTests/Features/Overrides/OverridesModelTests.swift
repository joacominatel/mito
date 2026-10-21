import MitoAssets
import MitoCore
import MitoImport
import Testing

@testable import Mito

private typealias Fixture = OverridesFixture

private let styles = Fixture.styles

/// A model loaded from `store`, with the editor open on `champion` in `role`.
private func editing(
    _ champion: ChampionID = Fixture.ahri, role: Role = .middle,
    store: OverridesTestStore = OverridesTestStore()
) async -> OverridesModel {
    let model = OverridesModel(store: store)
    await model.run()
    model.open(champion, role: role, styles: styles)
    return model
}

struct OverridesModelTests {
    // MARK: Listing and search

    @Test func runListsTheStoredOverridesByChampionName() async {
        let store = OverridesTestStore(overrides: [
            ChampionOverride(champion: Fixture.leeSin, role: .jungle),
            ChampionOverride(champion: Fixture.ahri, role: .middle),
            ChampionOverride(champion: Fixture.ahri, role: .top),
        ])
        let model = OverridesModel(store: store)

        await model.run()

        #expect(model.overrides.count == 3)
        let listed = model.listedOverrides(in: Fixture.gameData).map {
            "\($0.champion.rawValue) \($0.role.rawValue)"
        }
        #expect(listed == ["103 TOP", "103 MIDDLE", "64 JUNGLE"])
    }

    @Test func searchFiltersChampionsAndOverridesByName() async {
        let store = OverridesTestStore(overrides: [
            ChampionOverride(champion: Fixture.leeSin, role: .jungle),
            ChampionOverride(champion: Fixture.ahri, role: .middle),
        ])
        let model = OverridesModel(store: store)
        await model.run()

        #expect(model.champions(in: Fixture.gameData).map(\.name) == ["Aatrox", "Ahri", "Lee Sin"])

        model.searchText = "  lee "
        #expect(model.champions(in: Fixture.gameData).map(\.id) == [Fixture.leeSin])
        #expect(model.listedOverrides(in: Fixture.gameData).map(\.champion) == [Fixture.leeSin])

        model.searchText = "zed"
        #expect(model.champions(in: Fixture.gameData).isEmpty)
        #expect(model.listedOverrides(in: Fixture.gameData).isEmpty)
    }

    @Test func aFailedReadIsSurfaced() async {
        let model = OverridesModel(store: OverridesTestStore(failure: .readFailed))

        await model.run()

        #expect(model.failure == .load)
        #expect(model.overrides.isEmpty)
    }

    // MARK: Opening

    @Test func openingAChampionWithoutAnOverrideStartsFromTheDefaults() async {
        let model = await editing()

        #expect(model.draft?.runeMode == .adaptive)
        #expect(model.draft?.spellMode == .recommended)
        #expect(model.draft?.itemMode == .recommended)
        #expect(model.isStored == false)
        #expect(model.hasChanges == false)
        #expect(model.canSave(styles: styles) == false)
    }

    @Test func openingWithoutARoleUsesTheChampionsStoredRole() async {
        let store = OverridesTestStore(overrides: [
            ChampionOverride(champion: Fixture.leeSin, role: .jungle)
        ])
        let model = OverridesModel(store: store)
        await model.run()

        model.open(Fixture.leeSin, styles: styles)
        #expect(model.draft?.role == .jungle)

        model.open(Fixture.ahri, styles: styles)
        #expect(model.draft?.role == .top)
    }

    @Test func aSavedOverrideTakesItsStoreOrderForOpeningWithoutARole() async {
        let store = OverridesTestStore(overrides: [
            ChampionOverride(champion: Fixture.ahri, role: .middle)
        ])
        let model = await editing(role: .top, store: store)
        model.draft?.isFavorite = true
        await model.save(styles: styles)

        model.open(Fixture.ahri, styles: styles)
        #expect(model.draft?.role == .top)

        let relaunched = OverridesModel(store: store)
        await relaunched.run()
        relaunched.open(Fixture.ahri, styles: styles)
        #expect(relaunched.draft?.role == .top)
        #expect(model.overrides == relaunched.overrides)
    }

    @Test func theRoleSwitchesOnlyWithoutUnsavedChanges() async {
        let store = OverridesTestStore(overrides: [
            ChampionOverride(champion: Fixture.ahri, role: .top, isFavorite: true)
        ])
        let model = await editing(store: store)

        model.draft?.isExcludedFromPool = true
        model.switchRole(to: .top, styles: styles)
        #expect(model.draft?.role == .middle)

        model.draft?.isExcludedFromPool = false
        model.switchRole(to: .top, styles: styles)
        #expect(model.draft?.role == .top)
        #expect(model.draft?.isFavorite == true)
    }

    // MARK: Saving each mode

    @Test(arguments: [ChampionOverride.RuneMode.general, .adaptive])
    func aNonFixedRuneModeSavesWithoutAPage(mode: ChampionOverride.RuneMode) async {
        let store = OverridesTestStore(overrides: [
            ChampionOverride(champion: Fixture.ahri, role: .middle, runeMode: .fixed)
        ])
        let model = await editing(store: store)

        model.draft?.runeMode = mode
        await model.save(styles: styles)

        let saved = await store.stored
        #expect(saved.map(\.runeMode) == [mode])
        #expect(saved.first?.fixedPage == nil)
        #expect(model.isEditing == false)
    }

    @Test func aValidFixedPageIsSavedInClientOrder() async {
        let store = OverridesTestStore()
        let model = await editing(store: store)

        model.draft?.runeMode = .fixed
        model.draft?.runes = Fixture.validDraft()
        #expect(model.issues(styles: styles).isEmpty)
        await model.save(styles: styles)

        let saved = await store.stored
        #expect(saved.first?.runeMode == .fixed)
        #expect(saved.first?.fixedPage == Fixture.validPage)
        #expect(model.overrides.first?.fixedPage == Fixture.validPage)
    }

    @Test func anIncompleteFixedPageIsNotSaved() async {
        let store = OverridesTestStore()
        let model = await editing(store: store)

        model.draft?.runeMode = .fixed
        var runes = Fixture.validDraft()
        runes.shards[2] = nil
        model.draft?.runes = runes

        #expect(model.issues(styles: styles) == [.incompleteRunePage])
        #expect(model.canSave(styles: styles) == false)
        await model.save(styles: styles)
        #expect(await store.stored.isEmpty)
        #expect(model.isEditing)
    }

    enum InvalidPage: CaseIterable {
        case keystoneOutOfPlace
        case primaryPerkInTheWrongRow
        case shardInTheWrongRow
        case secondaryPerksShareARow
        case secondaryPerkFromThePrimaryTree
        case subStyleGoneFromTheClient
        case primaryWithoutShardRows

        var expected: RunePageValidationError {
            switch self {
            case .keystoneOutOfPlace: .perkOutOfPlace(index: 0, perk: PerkID(rawValue: 13))
            case .primaryPerkInTheWrongRow: .perkOutOfPlace(index: 1, perk: PerkID(rawValue: 15))
            case .shardInTheWrongRow: .perkOutOfPlace(index: 6, perk: PerkID(rawValue: 93))
            case .secondaryPerksShareARow: .secondaryPerksShareARow
            case .secondaryPerkFromThePrimaryTree:
                .perkOutOfPlace(index: 5, perk: PerkID(rawValue: 13))
            case .subStyleGoneFromTheClient: .unknownStyle(Fixture.domination)
            case .primaryWithoutShardRows: .unexpectedStyleLayout(Fixture.precision)
            }
        }

        /// The styles the page is validated against when saving.
        var clientStyles: [PerkStyle] {
            switch self {
            case .subStyleGoneFromTheClient: [Fixture.styles[0]]
            case .primaryWithoutShardRows:
                [Fixture.style(Fixture.precision, base: 10, shards: []), Fixture.styles[1]]
            default: Fixture.styles
            }
        }

        func apply(to runes: inout RunePageDraft) {
            switch self {
            case .keystoneOutOfPlace: runes.keystone = PerkID(rawValue: 13)
            case .primaryPerkInTheWrongRow: runes.primaryPerks[0] = PerkID(rawValue: 15)
            case .shardInTheWrongRow: runes.shards[0] = PerkID(rawValue: 93)
            case .secondaryPerksShareARow:
                runes.setSecondaryPerk(PerkID(rawValue: 24), inRow: 2)
            case .secondaryPerkFromThePrimaryTree:
                runes.setSecondaryPerk(PerkID(rawValue: 13), inRow: 2)
            case .subStyleGoneFromTheClient, .primaryWithoutShardRows: break
            }
        }
    }

    @Test(arguments: InvalidPage.allCases)
    func anInvalidFixedPageIsRejected(_ invalid: InvalidPage) async {
        let store = OverridesTestStore()
        let model = await editing(store: store)
        model.draft?.runeMode = .fixed
        var runes = Fixture.validDraft()
        invalid.apply(to: &runes)
        model.draft?.runes = runes

        #expect(model.issues(styles: invalid.clientStyles) == [.invalidRunePage(invalid.expected)])
        #expect(model.canSave(styles: invalid.clientStyles) == false)
        await model.save(styles: invalid.clientStyles)
        #expect(await store.stored.isEmpty)
    }

    @Test func fixedSpellsNeedTwoDifferentSpells() async {
        let store = OverridesTestStore()
        let model = await editing(store: store)
        model.draft?.spellMode = .fixed
        model.draft?.spells.first = SummonerSpellID(rawValue: 4)
        #expect(model.issues(styles: styles) == [.incompleteSpells])

        model.draft?.spells.second = SummonerSpellID(rawValue: 4)
        #expect(model.issues(styles: styles) == [.incompleteSpells])

        model.draft?.spells.second = SummonerSpellID(rawValue: 11)
        await model.save(styles: styles)

        let saved = await store.stored.first
        #expect(saved?.spellMode == .fixed)
        #expect(
            saved?.fixedSpells
                == SpellPair(
                    first: SummonerSpellID(rawValue: 4), second: SummonerSpellID(rawValue: 11)))
    }

    @Test func recommendedSpellsSave() async {
        let store = OverridesTestStore(overrides: [
            ChampionOverride(champion: Fixture.ahri, role: .middle, spellMode: .fixed)
        ])
        let model = await editing(store: store)

        model.draft?.spellMode = .recommended
        await model.save(styles: styles)

        #expect(await store.stored.map(\.spellMode) == [.recommended])
    }

    @Test func onlySummonersRiftSpellsAreOffered() {
        let model = OverridesModel()

        #expect(
            model.classicSpells(in: Fixture.gameData).map(\.name) == ["Flash", "Ignite", "Smite"])
    }

    @Test(arguments: [ChampionOverride.ItemMode.skip, .recommended])
    func itemModesWithoutASetSave(mode: ChampionOverride.ItemMode) async {
        let store = OverridesTestStore(overrides: [
            ChampionOverride(champion: Fixture.ahri, role: .middle, itemMode: .fixedSet)
        ])
        let model = await editing(store: store)

        model.draft?.itemMode = mode
        await model.save(styles: styles)

        #expect(await store.stored.map(\.itemMode) == [mode])
    }

    @Test func aFixedItemSetNeedsAnItemAndSavesItsBlocks() async throws {
        let store = OverridesTestStore()
        let model = await editing(store: store)
        model.draft?.itemMode = .fixedSet
        model.draft?.items.addBlock(title: "Inicio")
        #expect(model.issues(styles: styles) == [.emptyItemSet])

        let block = try #require(model.draft?.items.blocks.first?.id)
        model.draft?.items.add(ItemID(rawValue: 1056), to: block)
        model.draft?.items.add(ItemID(rawValue: 2003), to: block)
        model.draft?.items.add(ItemID(rawValue: 2003), to: block)
        model.draft?.items.addBlock(title: "Núcleo")
        await model.save(styles: styles)

        let saved = await store.stored.first
        #expect(saved?.itemMode == .fixedSet)
        #expect(
            saved?.fixedItems
                == ItemSet(blocks: [
                    ItemSet.Block(
                        title: "Inicio",
                        items: [
                            ItemSet.Block.Item(id: ItemID(rawValue: 1056)),
                            ItemSet.Block.Item(id: ItemID(rawValue: 2003), count: 2),
                        ]),
                    ItemSet.Block(title: "Núcleo", items: []),
                ]))
    }

    @Test func aCountUnderOneRemovesTheItem() throws {
        var items = ItemSetDraft(nil)
        items.addBlock(title: "Inicio")
        let block = try #require(items.blocks.first?.id)
        items.add(ItemID(rawValue: 1056), to: block)

        items.setCount(0, of: ItemID(rawValue: 1056), in: block)

        #expect(items.blocks.first?.items.isEmpty == true)
        #expect(items.itemSet == nil)
    }

    @Test func itemSearchMatchesByNameAndNeedsAQuery() {
        let model = OverridesModel()
        #expect(model.itemResults(in: Fixture.gameData).isEmpty)

        model.itemQuery = "doran"

        #expect(
            model.itemResults(in: Fixture.gameData).map(\.name) == [
                "Doran's Blade", "Doran's Ring",
            ])
    }

    // MARK: Favorite and exclusion

    @Test func favoriteAndExclusionRoundTrip() async {
        let store = OverridesTestStore()
        let first = await editing(store: store)
        first.draft?.isFavorite = true
        first.draft?.isExcludedFromPool = true
        await first.save(styles: styles)

        let second = await editing(store: store)

        #expect(second.isStored)
        #expect(second.draft?.isFavorite == true)
        #expect(second.draft?.isExcludedFromPool == true)
    }

    @Test func aStoredFixedOverrideReopensUnchanged() async {
        let override = ChampionOverride(
            champion: Fixture.ahri, role: .middle, runeMode: .fixed, fixedPage: Fixture.validPage,
            spellMode: .fixed,
            fixedSpells: SpellPair(
                first: SummonerSpellID(rawValue: 4), second: SummonerSpellID(rawValue: 14)),
            itemMode: .fixedSet,
            fixedItems: ItemSet(blocks: [
                ItemSet.Block(
                    title: "Inicio", items: [ItemSet.Block.Item(id: ItemID(rawValue: 1056))])
            ]))
        let model = await editing(store: OverridesTestStore(overrides: [override]))

        #expect(model.draft?.override(styles: styles) == override)
    }

    // MARK: Delete and failures

    @Test func deleteRemovesTheOverrideAndClosesTheEditor() async {
        let store = OverridesTestStore(overrides: [
            ChampionOverride(champion: Fixture.ahri, role: .middle, isFavorite: true),
            ChampionOverride(champion: Fixture.ahri, role: .top),
        ])
        let model = await editing(store: store)

        await model.delete()

        #expect(await store.stored.map(\.role) == [.top])
        #expect(model.overrides.map(\.role) == [.top])
        #expect(model.isEditing == false)
    }

    @Test func aFailedSaveKeepsTheEditorOpen() async {
        let store = OverridesTestStore()
        let model = await editing(store: store)
        await store.fail(with: .writeFailed)

        model.draft?.isFavorite = true
        await model.save(styles: styles)

        #expect(model.failure == .save)
        #expect(model.isEditing)
        #expect(model.overrides.isEmpty)

        await store.fail(with: nil)
        await model.save(styles: styles)
        #expect(model.failure == nil)
        #expect(await store.stored.count == 1)
    }

    @Test func aFailedDeleteKeepsTheOverride() async {
        let store = OverridesTestStore(overrides: [
            ChampionOverride(champion: Fixture.ahri, role: .middle)
        ])
        let model = await editing(store: store)
        await store.fail(with: .writeFailed)

        await model.delete()

        #expect(model.failure == .delete)
        #expect(model.overrides.count == 1)
        #expect(model.isEditing)
    }
}

struct OverridesGapTests {
    /// The store lists a champion's roles in `Role.allCases` order, so top comes before middle.
    @Test func openingWithoutARolePicksTheFirstStoredRoleInRoleOrder() async {
        let store = OverridesTestStore(overrides: [
            ChampionOverride(champion: Fixture.ahri, role: .middle),
            ChampionOverride(champion: Fixture.ahri, role: .top, isFavorite: true),
        ])
        let model = OverridesModel(store: store)
        await model.run()

        model.open(Fixture.ahri, styles: styles)

        #expect(model.draft?.role == .top)
        #expect(model.draft?.isFavorite == true)
    }

    @Test func aRenamedAndARemovedBlockAreSavedThatWay() async throws {
        let store = OverridesTestStore()
        let model = await editing(store: store)
        model.draft?.itemMode = .fixedSet
        model.draft?.items.addBlock(title: "Inicio")
        model.draft?.items.addBlock(title: "Sobra")
        let blocks = try #require(model.draft?.items.blocks.map(\.id))
        model.draft?.items.add(ItemID(rawValue: 1056), to: blocks[0])
        model.draft?.items.add(ItemID(rawValue: 2003), to: blocks[1])

        model.draft?.items.setTitle("Arranque", of: blocks[0])
        model.draft?.items.setCount(3, of: ItemID(rawValue: 1056), in: blocks[0])
        model.draft?.items.removeBlock(blocks[1])
        await model.save(styles: styles)

        #expect(
            await store.stored.first?.fixedItems
                == ItemSet(blocks: [
                    ItemSet.Block(
                        title: "Arranque",
                        items: [ItemSet.Block.Item(id: ItemID(rawValue: 1056), count: 3)])
                ]))
    }

    @Test func closingTheSheetDropsTheDraft() async {
        let model = await editing()

        model.isEditing = false

        #expect(model.draft == nil)
        #expect(!model.hasChanges)
    }
}
