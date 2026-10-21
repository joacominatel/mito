import Foundation
import LCUKit
import MitoAssets
import MitoCore
import MitoImport
import MitoStore
import Testing

@testable import Mito

private let ahri = ChampionID(rawValue: 103)
private let zed = ChampionID(rawValue: 238)
private let mySelectionPath = "/lol-champ-select/v1/session/my-selection"
private let pagesPath = LCUEndpoint.perkPages.path
private let itemSetsPath = LCUEndpoint.itemSets(summonerId: 1).path

private nonisolated struct NoStats: StatsProvider {
    func roleGames(for champion: ChampionID) -> [Role: Int] { [:] }
}

/// One model over the snapshot contract fixture and a scripted connection that serves the
/// recorded cases, and a recording poster.
private struct Harness {
    let connection = ImportTestConnection()
    let poster = RecordingPoster()
    let store: ImportTestStore
    let model: ImportModel

    init(
        settings: ImportSettings = ImportSettings(), windowInFront: Bool = false,
        stats: (any StatsProvider)? = nil, overrides: [ChampionOverride] = [],
        detectedFlash: ImportSettings.FlashPosition? = nil,
        personal: (any PersonalStore)? = nil, servesGameData: Bool = true
    ) throws {
        let stats = try stats ?? SnapshotFixture.reader()
        let store = ImportTestStore(overrides: overrides)
        self.store = store
        model = ImportModel(
            connection: connection, catalog: GameDataCatalog(connection: connection),
            settings: { settings }, stats: { stats }, store: personal ?? store,
            detectedFlash: { detectedFlash }, poster: poster, appIsActive: { true })
        if windowInFront { model.windowAppeared() }
        if servesGameData {
            for (path, body) in ImportFixture.gameData { connection.serve(path, body) }
        }
        connection.serve(LCUEndpoint.perkStyles.path, try ImportFixture.data("styles", in: "runes"))
        connection.serve(pagesPath, try ImportFixture.data("pages-without-mito-page", in: "runes"))
        connection.serve(
            LCUEndpoint.perkInventory.path,
            try ImportFixture.data("inventory-with-room", in: "runes"))
        connection.serve(
            LCUEndpoint.gameflowSession.path,
            try ImportFixture.data("session-ranked-solo", in: "gameflow-lobby"))
        connection.serve(
            LCUEndpoint.currentSummoner.path, try ImportFixture.data("full", in: "session"))
        connection.serve(itemSetsPath, try ImportFixture.data("empty", in: "item-sets"))
    }

    func start() -> Task<Void, Never> {
        let model = model
        return Task { await model.run() }
    }

    /// Returns once every event emitted so far has been handled.
    func stop(_ run: Task<Void, Never>) async {
        connection.finish()
        await run.value
    }

    /// The fixture's player already has Flash and Ignite, Ahri's spells: they are never sent.
    var spellWrites: Int { connection.writes(.patch, mySelectionPath).count }

    func runePageWrites() -> [ImportTestConnection.Request] {
        connection.requests.filter { $0.method != .get && $0.path.hasPrefix(pagesPath) }
    }

    var writes: [ImportTestConnection.Request] {
        connection.requests.filter { $0.method != .get }
    }

    func sentSpells() throws -> [String: Int]? {
        let body = try #require(connection.writes(.patch, mySelectionPath).first?.body)
        return try JSONSerialization.jsonObject(with: body) as? [String: Int]
    }

    func sentRunePage() throws -> [String: Any]? {
        let body = try #require(runePageWrites().first?.body)
        return try JSONSerialization.jsonObject(with: body) as? [String: Any]
    }

    /// The Mito set in the item sets `PUT`.
    func sentItemSet() throws -> [String: Any]? {
        let put = try #require(connection.writes(.put, itemSetsPath).first?.body)
        let sets = (try JSONSerialization.jsonObject(with: put) as? [String: Any])?["itemSets"]
        return (sets as? [[String: Any]])?.last
    }
}

@Suite(.timeLimit(.minutes(1)))
struct ImportTriggerTests {
    @Test func importsWhenThePickLocks() async throws {
        let harness = try Harness()
        let run = harness.start()

        harness.connection.emit(try ImportFixture.lockedSession())
        await waitUntil { !harness.poster.posts.isEmpty }
        await harness.stop(run)

        #expect(
            harness.poster.posts == [
                .init(
                    notification: .loadoutImported(champion: ahri, opponent: nil),
                    title: "Importado para Ahri MID")
            ])
        #expect(harness.runePageWrites().count == 1)
        #expect(harness.connection.writes(.put, itemSetsPath).count == 1)
        #expect(harness.spellWrites == 0)
    }

    @Test func sendsTheBuildsSpellsWhenTheyDiffer() async throws {
        let harness = try Harness()
        let run = harness.start()

        harness.connection.emit(try ImportFixture.lockedSession(mySpells: [4, 12]))
        await harness.stop(run)

        #expect(try harness.sentSpells() == ["spell1Id": 4, "spell2Id": 14])
    }

    @Test func aHoverImportsNothingByDefault() async throws {
        let harness = try Harness()
        let run = harness.start()

        harness.connection.emit(try ImportFixture.data("ban-pick-in-progress"))
        await harness.stop(run)

        #expect(harness.connection.requests.isEmpty)
        #expect(harness.poster.posts.isEmpty)
    }

    @Test func aHoverImportsWithImportOnHover() async throws {
        let harness = try Harness(settings: ImportSettings(importOnHover: true))
        let run = harness.start()

        harness.connection.emit(try ImportFixture.data("ban-pick-in-progress"))
        await waitUntil { !harness.poster.posts.isEmpty }
        await harness.stop(run)

        #expect(
            harness.poster.posts.map(\.notification) == [
                .loadoutImported(champion: ahri, opponent: nil)
            ])
        #expect(harness.runePageWrites().count == 1)
    }

    @Test func importsOncePerChampionInOneChampSelect() async throws {
        let harness = try Harness(settings: ImportSettings(importOnHover: true))
        let run = harness.start()

        harness.connection.emit(try ImportFixture.data("ban-pick-in-progress"))
        harness.connection.emit(try ImportFixture.lockedSession())
        harness.connection.emit(try ImportFixture.lockedSession())
        await harness.stop(run)

        #expect(harness.poster.posts.count == 1)
        #expect(harness.runePageWrites().count == 1)
    }

    @Test func aNewChampSelectImportsAgain() async throws {
        let harness = try Harness()
        let run = harness.start()

        harness.connection.emit(try ImportFixture.lockedSession())
        harness.connection.emitDelete()
        harness.connection.emit(try ImportFixture.lockedSession())
        await harness.stop(run)

        #expect(harness.poster.posts.count == 2)
        #expect(harness.runePageWrites().count == 2)
    }

    @Test func aChampionWithoutStatsImportsNothing() async throws {
        let harness = try Harness()
        let run = harness.start()

        harness.connection.emit(try ImportFixture.lockedSession(champion: 1))
        await harness.stop(run)

        #expect(harness.connection.requests.isEmpty)
        #expect(harness.poster.posts.isEmpty)
        #expect(harness.model.outcome == nil)
    }
}

@Suite(.timeLimit(.minutes(1)))
struct ImportContextTests {
    @Test func namesThePageAndTheSetAfterTheChampionAndRole() async throws {
        let harness = try Harness()
        let run = harness.start()

        harness.connection.emit(try ImportFixture.lockedSession())
        await harness.stop(run)

        let page = try #require(harness.runePageWrites().first?.body)
        let sentPage = try JSONSerialization.jsonObject(with: page) as? [String: Any]
        #expect(sentPage?["name"] as? String == "Mito · Ahri MID")

        let put = try #require(harness.connection.writes(.put, itemSetsPath).first?.body)
        let sets = try #require(
            (try JSONSerialization.jsonObject(with: put) as? [String: Any])?["itemSets"]
                as? [[String: Any]])
        #expect(sets.count == 1)
        #expect(sets.first?["title"] as? String == "Mito · Ahri MID")
        #expect(sets.first?["map"] as? String == "SR")
        #expect(sets.first?["associatedMaps"] as? [Int] == [11])
        #expect(sets.first?["associatedChampions"] as? [Int] == [103])
    }

    @Test func readsTheItemSetsOfTheSignedInSummoner() async throws {
        let harness = try Harness()
        let run = harness.start()

        harness.connection.emit(try ImportFixture.lockedSession())
        await harness.stop(run)

        #expect(harness.connection.writes(.get, itemSetsPath).count == 1)
        #expect(harness.connection.writes(.put, itemSetsPath).count == 1)
    }

    @Test func anotherMapSkipsTheItemsAndSaysSo() async throws {
        let harness = try Harness(windowInFront: true)
        harness.connection.serve(
            LCUEndpoint.gameflowSession.path,
            try ImportFixture.data("session-aram", in: "gameflow-lobby"))
        let run = harness.start()

        harness.connection.emit(try ImportFixture.lockedSession())
        await harness.stop(run)

        let outcome = try #require(harness.model.outcome)
        #expect(outcome.itemsUnavailable == .unsupportedMap)
        #expect(outcome.report.items == .skipped(.notInLoadout))
        #expect(outcome.report.runes == .applied)
        #expect(String(localized: outcome.rows[2].status) == "No disponible en este mapa")
        #expect(!harness.connection.requests.contains { $0.path.hasPrefix("/lol-item-sets") })
    }

    @Test func anUnreadableSummonerSkipsTheItems() async throws {
        let harness = try Harness(windowInFront: true)
        harness.connection.serve(LCUEndpoint.currentSummoner.path, Data("{}".utf8))
        let run = harness.start()

        harness.connection.emit(try ImportFixture.lockedSession())
        await harness.stop(run)

        #expect(harness.model.outcome?.itemsUnavailable == .noAccount)
        #expect(!harness.connection.requests.contains { $0.path.hasPrefix("/lol-item-sets") })
    }
}

/// The general loadout comes from the snapshot through `LoadoutSelection` (§18.6–§18.9).
@Suite(.timeLimit(.minutes(1)))
struct ImportSnapshotTests {
    @Test func ahriMiddleImportsTheEnginesChoiceWithTitledBlocks() async throws {
        let harness = try Harness(windowInFront: true)
        let run = harness.start()

        harness.connection.emit(try ImportFixture.lockedSession(mySpells: [4, 12]))
        await harness.stop(run)

        let page = try #require(try harness.sentRunePage())
        #expect(page["primaryStyleId"] as? Int == 8200)
        #expect(page["subStyleId"] as? Int == 8300)
        #expect(
            page["selectedPerkIds"] as? [Int]
                == [8229, 8226, 8210, 8237, 8304, 8347, 5007, 5008, 5011])
        #expect(try harness.sentSpells() == ["spell1Id": 4, "spell2Id": 14])

        let blocks = try #require(try harness.sentItemSet()?["blocks"] as? [[String: Any]])
        #expect(
            blocks.map { $0["type"] as? String }
                == ["Inicio", "Núcleo", "Botas", "4.º ítem", "5.º ítem"])
        let items = blocks.map { block in
            (block["items"] as? [[String: Any]] ?? []).map {
                "\($0["id"] as? String ?? "?")x\($0["count"] as? Int ?? 0)"
            }
        }
        #expect(
            items == [
                ["1056x1", "2003x2"], ["6655x1", "3157x1", "3089x1"], ["3020x1"], ["3107x1"],
                ["3142x1"],
            ])
        #expect(harness.model.outcome?.status == .imported)
    }

    @Test func marksTheLowSampleParts() async throws {
        let harness = try Harness(windowInFront: true)
        let run = harness.start()

        harness.connection.emit(
            try ImportFixture.lockedSession(champion: 238, mySpells: [4, 14], position: "jungle"))
        await harness.stop(run)

        // Zed JUNGLE: the page has 687 games (under rune_page's 800) and the start 32 (under
        // build_layer's 100); the spells are reliable.
        let outcome = try #require(harness.model.outcome)
        #expect(outcome.title == "Zed JGL")
        #expect(outcome.status == .imported)
        #expect(outcome.rows.map(\.isLowSample) == [true, false, true])
    }

    @Test func ahriMiddleMarksItsRunesAndItems() async throws {
        let harness = try Harness(windowInFront: true)
        let run = harness.start()

        harness.connection.emit(try ImportFixture.lockedSession(mySpells: [4, 12]))
        await harness.stop(run)

        let outcome = try #require(harness.model.outcome)
        #expect(outcome.rows.map(\.isLowSample) == [true, false, true])
    }

    @Test func aSkippedPartCarriesNoLowSampleMark() async throws {
        let harness = try Harness(
            settings: ImportSettings(importRunes: false), windowInFront: true)
        let run = harness.start()

        harness.connection.emit(try ImportFixture.lockedSession(mySpells: [4, 12]))
        await harness.stop(run)

        #expect(harness.model.outcome?.rows.first?.isLowSample == false)
    }

    @Test func blindPickUsesTheChampionsMostPlayedRole() async throws {
        let harness = try Harness(windowInFront: true)
        let run = harness.start()

        // Zed: 2,746 JUNGLE games against 2,195 MIDDLE.
        harness.connection.emit(
            try ImportFixture.lockedSession(champion: 238, mySpells: [4, 14], position: ""))
        await harness.stop(run)

        #expect(harness.model.outcome?.title == "Zed JGL")
        #expect(try harness.sentSpells() == ["spell1Id": 4, "spell2Id": 11])
    }

    @Test func blindPickWithoutRoleDataImportsNothing() async throws {
        let harness = try Harness(windowInFront: true)
        let run = harness.start()

        harness.connection.emit(try ImportFixture.lockedSession(champion: 1, position: ""))
        await harness.stop(run)

        #expect(harness.connection.requests.isEmpty)
        #expect(harness.model.outcome == nil)
    }

    @Test func mostPlayedRoleBreaksTiesInRoleOrder() throws {
        let stats = try SnapshotFixture.reader()

        #expect(ImportModel.mostPlayedRole(of: zed, in: stats) == .jungle)
        #expect(ImportModel.mostPlayedRole(of: ChampionID(rawValue: 1), in: stats) == nil)
        #expect(ImportModel.mostPlayedRole(of: ahri, in: TiedStats()) == .top)
    }

    @Test func withoutASnapshotImportsNothingAndSaysSoOnce() async throws {
        let harness = try Harness(settings: ImportSettings(importOnHover: true), stats: NoStats())
        let run = harness.start()

        harness.connection.emit(try ImportFixture.data("ban-pick-in-progress"))
        harness.connection.emit(try ImportFixture.lockedSession(champion: 238))
        await harness.stop(run)

        #expect(harness.writes.isEmpty)
        #expect(
            harness.poster.posts.map(\.title) == [
                "Sin estadísticas del parche: no se importó nada para Ahri MID"
            ])
    }

    @Test func withoutASnapshotTheToastHasNoRows() async throws {
        let harness = try Harness(windowInFront: true, stats: NoStats())
        let run = harness.start()

        harness.connection.emit(try ImportFixture.lockedSession())
        await harness.stop(run)

        let outcome = try #require(harness.model.outcome)
        #expect(outcome.status == .noStats)
        #expect(outcome.rows.isEmpty)
        #expect(harness.writes.isEmpty)
    }

    @Test func aNewChampSelectSaysItAgain() async throws {
        let harness = try Harness(stats: NoStats())
        let run = harness.start()

        harness.connection.emit(try ImportFixture.lockedSession())
        harness.connection.emitDelete()
        harness.connection.emit(try ImportFixture.lockedSession())
        await harness.stop(run)

        #expect(harness.poster.posts.count == 2)
    }

    private struct TiedStats: StatsProvider {
        func roleGames(for champion: ChampionID) -> [Role: Int] { [.middle: 5, .top: 5] }
    }
}

@Suite(.timeLimit(.minutes(1)))
struct ImportFeedbackTests {
    @Test func showsAToastWhileTheWindowIsInFront() async throws {
        let harness = try Harness(windowInFront: true)
        let run = harness.start()

        harness.connection.emit(try ImportFixture.lockedSession())
        await harness.stop(run)

        let outcome = try #require(harness.model.outcome)
        #expect(outcome.status == .imported)
        #expect(String(localized: outcome.headline) == "Importado para Ahri MID")
        #expect(harness.poster.posts.isEmpty)
    }

    @Test func postsANotificationOnceTheWindowCloses() async throws {
        let harness = try Harness(windowInFront: true)
        harness.model.windowDisappeared()
        let run = harness.start()

        harness.connection.emit(try ImportFixture.lockedSession())
        await harness.stop(run)

        #expect(harness.model.outcome == nil)
        #expect(harness.poster.posts.count == 1)
    }

    @Test func postsANotificationWhileAnotherAppIsInFront() async throws {
        let connection = ImportTestConnection()
        let poster = RecordingPoster()
        let stats = try SnapshotFixture.reader()
        let model = ImportModel(
            connection: connection, catalog: GameDataCatalog(connection: connection),
            stats: { stats }, poster: poster, appIsActive: { false })
        model.windowAppeared()
        for (path, body) in ImportFixture.gameData { connection.serve(path, body) }

        // No rune data served: the runes fail, which still reports.
        let run = Task { await model.run() }
        connection.emit(try ImportFixture.lockedSession())
        connection.finish()
        await run.value

        #expect(model.outcome == nil)
        #expect(poster.posts.map(\.title) == ["No se pudo importar todo para Ahri MID"])
    }

    @Test func theTimeoutDismissesAToast() async throws {
        let harness = try Harness(windowInFront: true)
        let run = harness.start()
        harness.connection.emit(try ImportFixture.lockedSession())
        await harness.stop(run)
        let id = try #require(harness.model.outcome?.id)

        harness.model.dismiss(id)

        #expect(harness.model.outcome == nil)
    }
}

@Suite(.timeLimit(.minutes(1)))
struct ImportConfirmationTests {
    /// No free slot and no Mito page: the current page "My page" (201) is the user's.
    private func fullHarness(windowInFront: Bool = true) throws -> Harness {
        let harness = try Harness(windowInFront: windowInFront)
        harness.connection.serve(
            LCUEndpoint.perkInventory.path, try ImportFixture.data("inventory-full", in: "runes"))
        return harness
    }

    @Test func asksBeforeReplacingTheUsersPage() async throws {
        let harness = try fullHarness()
        let run = harness.start()

        harness.connection.emit(try ImportFixture.lockedSession())
        await harness.stop(run)

        let outcome = try #require(harness.model.outcome)
        #expect(outcome.status == .needsConfirmation(pageID: 201, pageName: "My page"))
        #expect(harness.runePageWrites().isEmpty)
        #expect(String(localized: outcome.rows[0].status) == "¿Reemplazar «My page»?")
    }

    @Test func confirmingReappliesTheRunesOverThatPage() async throws {
        let harness = try fullHarness()
        let run = harness.start()
        harness.connection.emit(try ImportFixture.lockedSession())
        await harness.stop(run)

        await harness.model.confirmReplacement()

        #expect(harness.runePageWrites().map(\.path) == ["\(pagesPath)/201"])
        #expect(harness.runePageWrites().first?.method == .put)
        #expect(harness.model.outcome?.report.runes == .applied)
        #expect(harness.model.outcome?.status == .imported)
        #expect(harness.connection.writes(.put, itemSetsPath).count == 1)
        #expect(harness.spellWrites == 0)
    }

    @Test func aDismissTimeoutLeavesTheConfirmation() async throws {
        let harness = try fullHarness()
        let run = harness.start()
        harness.connection.emit(try ImportFixture.lockedSession())
        await harness.stop(run)
        let id = try #require(harness.model.outcome?.id)

        harness.model.dismiss(id)

        #expect(harness.model.outcome?.needsConfirmation == true)
    }

    @Test func decliningSendsNothing() async throws {
        let harness = try fullHarness()
        let run = harness.start()
        harness.connection.emit(try ImportFixture.lockedSession())
        await harness.stop(run)

        harness.model.declineReplacement()
        await harness.model.confirmReplacement()

        #expect(harness.model.outcome == nil)
        #expect(harness.runePageWrites().isEmpty)
    }

    @Test func theConfirmationWaitsInTheMenuWithTheWindowClosed() async throws {
        let harness = try fullHarness(windowInFront: false)
        let run = harness.start()
        harness.connection.emit(try ImportFixture.lockedSession())
        await harness.stop(run)

        #expect(harness.model.outcome?.needsConfirmation == true)
        #expect(harness.poster.posts.map(\.title) == ["Confirmá las runas para Ahri MID"])
        #expect(harness.runePageWrites().isEmpty)
    }

    @Test func aNewChampSelectDropsTheConfirmation() async throws {
        let harness = try fullHarness()
        let run = harness.start()
        harness.connection.emit(try ImportFixture.lockedSession())
        harness.connection.emitDelete()
        await harness.stop(run)

        await harness.model.confirmReplacement()

        #expect(harness.model.outcome == nil)
        #expect(harness.runePageWrites().isEmpty)
    }
}

@Suite(.timeLimit(.minutes(1)))
struct ImportSettingsSupportTests {
    @Test func listsOnlyTheEditableRunePages() async throws {
        let connection = ImportTestConnection()
        connection.serve(
            LCUEndpoint.perkPages.path,
            try ImportFixture.data("pages-without-mito-page", in: "runes"))
        let model = ImportModel(
            connection: connection, catalog: GameDataCatalog(connection: connection))

        await model.loadEditablePages()

        #expect(model.editablePages.map(\.id) == [201, 203])
    }
}

struct AutoAcceptQuickToggleTests {
    @Test func turningItOffStopsAutoAccept() {
        var settings = GameSettings(autoAccept: .selectedQueues)
        #expect(settings.isAutoAcceptOn)

        settings.isAutoAcceptOn = false

        #expect(settings.autoAccept == .off)
    }

    @Test func turningItOnAcceptsAlways() {
        var settings = GameSettings(autoAccept: .off)
        #expect(!settings.isAutoAcceptOn)

        settings.isAutoAcceptOn = true

        #expect(settings.autoAccept == .always)
    }

    @Test func turningItOnKeepsAQueueSelection() {
        var settings = GameSettings(autoAccept: .selectedQueues)

        settings.isAutoAcceptOn = true

        #expect(settings.autoAccept == .selectedQueues)
    }
}

/// A valid Domination page against `runes/styles.json`, unlike the engine's Sorcery one.
private let fixedPage = RunePage(
    primaryStyle: PerkStyleID(rawValue: 8100), subStyle: PerkStyleID(rawValue: 8200),
    perks: [8112, 8139, 8140, 8135, 8226, 8210, 5008, 5008, 5001].map(PerkID.init(rawValue:)))
private let teleportAndFlash = SpellPair(
    first: SummonerSpellID(rawValue: 12), second: SummonerSpellID(rawValue: 4))
private let fixedItems = ItemSet(blocks: [
    ItemSet.Block(title: "Mi set", items: [ItemSet.Block.Item(id: ItemID(rawValue: 3089))])
])

/// Everything fixed for Ahri MID.
private func ahriOverride(
    runeMode: ChampionOverride.RuneMode = .fixed, page: RunePage? = fixedPage,
    spellMode: ChampionOverride.SpellMode = .fixed, spells: SpellPair? = teleportAndFlash,
    itemMode: ChampionOverride.ItemMode = .fixedSet, items: ItemSet? = fixedItems
) -> ChampionOverride {
    ChampionOverride(
        champion: ahri, role: .middle, runeMode: runeMode, fixedPage: page,
        spellMode: spellMode, fixedSpells: spells, itemMode: itemMode, fixedItems: items)
}

/// One locked Ahri MID import with the window in front; the player holds Flash on D and Ignite.
private func importAhri(
    settings: ImportSettings = ImportSettings(), overrides: [ChampionOverride],
    detectedFlash: ImportSettings.FlashPosition? = nil, mySpells: [Int] = [4, 14],
    prepare: (Harness) throws -> Void = { _ in }
) async throws -> Harness {
    let harness = try Harness(
        settings: settings, windowInFront: true, overrides: overrides,
        detectedFlash: detectedFlash)
    try prepare(harness)
    let run = harness.start()
    harness.connection.emit(try ImportFixture.lockedSession(mySpells: mySpells))
    await harness.stop(run)
    return harness
}

/// §13.1 and §21.5: the champion's override over the general loadout.
@Suite(.timeLimit(.minutes(1)))
struct ImportOverrideTests {
    @Test func aFixedRuneOverrideSendsTheSavedPage() async throws {
        let harness = try await importAhri(overrides: [ahriOverride()])

        let page = try #require(try harness.sentRunePage())
        #expect(page["primaryStyleId"] as? Int == 8100)
        #expect(
            page["selectedPerkIds"] as? [Int]
                == [8112, 8139, 8140, 8135, 8226, 8210, 5008, 5008, 5001])
        let runes = try #require(harness.model.outcome?.rows.first)
        #expect(runes.origin == .override)
        #expect(String(localized: try #require(runes.origin).marker) == "· override")
        // Ahri's general page is low sample; the user's own page is not.
        #expect(!runes.isLowSample)
    }

    @Test func aGeneralOverrideBeatsTheGlobalFixedPerChampion() async throws {
        let harness = try await importAhri(
            settings: ImportSettings(runeMode: .fixedPerChampion),
            overrides: [ahriOverride(runeMode: .general)])

        #expect(try harness.sentRunePage()?["primaryStyleId"] as? Int == 8200)
        #expect(harness.model.outcome?.origins[.runes] == nil)
    }

    @Test func anAdaptiveOverrideFollowsTheGlobalFixedPerChampion() async throws {
        // `.adaptive` is the editor's default: no preference of its own.
        let harness = try await importAhri(
            settings: ImportSettings(runeMode: .fixedPerChampion),
            overrides: [ahriOverride(runeMode: .adaptive)])

        #expect(try harness.sentRunePage()?["primaryStyleId"] as? Int == 8100)
        #expect(harness.model.outcome?.origins[.runes] == .override)
    }

    @Test(arguments: [ImportSettings.RuneMode.adaptive, .general])
    func anAdaptiveOverrideUnderAGeneralGlobalModeSendsTheGeneralPage(
        global: ImportSettings.RuneMode
    ) async throws {
        // A saved page is ignored: only "fijo por campeón" or the override's `.fixed` use it.
        let harness = try await importAhri(
            settings: ImportSettings(runeMode: global),
            overrides: [ahriOverride(runeMode: .adaptive)])

        #expect(try harness.sentRunePage()?["primaryStyleId"] as? Int == 8200)
        #expect(harness.model.outcome?.origins[.runes] == nil)
    }

    @Test func anInvalidFixedPageIsShownAndNotSent() async throws {
        let stale = RunePage(
            primaryStyle: PerkStyleID(rawValue: 8400), subStyle: PerkStyleID(rawValue: 8200),
            perks: fixedPage.perks)
        let harness = try await importAhri(overrides: [ahriOverride(page: stale)])

        #expect(harness.runePageWrites().isEmpty)
        let outcome = try #require(harness.model.outcome)
        #expect(
            outcome.report.runes
                == .failed(.invalidRunePage(.unknownStyle(PerkStyleID(rawValue: 8400)))))
        #expect(
            String(localized: outcome.rows[0].status)
                == "Página inválida (una rama ya no existe), no se envió")
        #expect(outcome.rows[0].origin == .override)
    }

    @Test func fixedPerChampionUsesTheSavedPage() async throws {
        // An override whose rune mode this build does not know follows the global mode.
        let harness = try await importAhri(
            settings: ImportSettings(runeMode: .fixedPerChampion),
            overrides: [ahriOverride(runeMode: .unknown("matchup_v2"))])

        #expect(try harness.sentRunePage()?["primaryStyleId"] as? Int == 8100)
        #expect(harness.model.outcome?.origins[.runes] == .override)
    }

    @Test func fixedPerChampionWithoutAPageSendsTheGeneralOneAndSaysSo() async throws {
        let harness = try await importAhri(
            settings: ImportSettings(runeMode: .fixedPerChampion), overrides: [])

        #expect(try harness.sentRunePage()?["primaryStyleId"] as? Int == 8200)
        let runes = try #require(harness.model.outcome?.rows.first)
        #expect(runes.origin == .noFixedChoice)
        #expect(
            String(localized: try #require(runes.origin).marker)
                == "· sin fija guardada, va la general")
        #expect(runes.isLowSample)
    }

    @Test func fixedSpellsKeepTheFlashRule() async throws {
        // Teleport + Flash with Flash on D in the session: Flash stays on D.
        let harness = try await importAhri(overrides: [ahriOverride()])

        #expect(try harness.sentSpells() == ["spell1Id": 4, "spell2Id": 12])
        #expect(harness.model.outcome?.origins[.spells] == .override)
    }

    @Test func recommendedSpellsSendTheEnginePair() async throws {
        let harness = try await importAhri(
            overrides: [ahriOverride(spellMode: .recommended)], mySpells: [4, 12])

        #expect(try harness.sentSpells() == ["spell1Id": 4, "spell2Id": 14])
        #expect(harness.model.outcome?.origins[.spells] == nil)
    }

    @Test func aFixedSetIsSentAsMitosSet() async throws {
        let harness = try await importAhri(overrides: [ahriOverride()])

        let set = try #require(try harness.sentItemSet())
        #expect(set["title"] as? String == "Mito · Ahri MID")
        #expect((set["uid"] as? String)?.hasPrefix("mito-") == true)
        let blocks = try #require(set["blocks"] as? [[String: Any]])
        #expect(blocks.map { $0["type"] as? String } == ["Mi set"])
        #expect(harness.model.outcome?.rows[2].origin == .override)
    }

    @Test func recommendedItemsSendTheEngineBuild() async throws {
        let harness = try await importAhri(overrides: [ahriOverride(itemMode: .recommended)])

        let blocks = try #require(try harness.sentItemSet()?["blocks"] as? [[String: Any]])
        #expect(blocks.first?["type"] as? String == "Inicio")
    }

    @Test func skippingItemsKeepsTheOldMitoSet() async throws {
        let harness = try await importAhri(overrides: [ahriOverride(itemMode: .skip)]) {
            $0.connection.serve(
                itemSetsPath, try ImportFixture.data("old-mito-sets", in: "item-sets"))
        }

        #expect(!harness.connection.requests.contains { $0.path.hasPrefix("/lol-item-sets") })
        let outcome = try #require(harness.model.outcome)
        #expect(outcome.itemsUnavailable == .skippedByOverride)
        #expect(String(localized: outcome.rows[2].status) == "No se importan")
        #expect(outcome.rows[2].origin == .override)
        #expect(outcome.status == .imported)
    }

    @Test func partsSwitchedOffInSettingsIgnoreTheOverride() async throws {
        let harness = try await importAhri(
            settings: ImportSettings(
                importRunes: false, importSpells: false, importItemSets: false),
            overrides: [ahriOverride(itemMode: .skip)])

        #expect(harness.writes.isEmpty)
        #expect(harness.model.outcome == nil)
        #expect(
            await harness.store.log.map(\.detail) == ["disabled", "disabled", "disabled"])
    }

    @Test func aSwitchedOffPartIsSkippedWhileTheOthersFollowTheOverride() async throws {
        let harness = try await importAhri(
            settings: ImportSettings(importRunes: false), overrides: [ahriOverride()])

        #expect(harness.runePageWrites().isEmpty)
        let outcome = try #require(harness.model.outcome)
        #expect(outcome.report.runes == .skipped(.disabled))
        #expect(outcome.origins == [.spells: .override, .items: .override])
    }

    @Test func anOverrideForAnotherRoleOrOnlyMarksChangesNothing() async throws {
        let plain = try await importAhri(overrides: [], mySpells: [4, 12])
        let other = try await importAhri(
            overrides: [
                ChampionOverride(
                    champion: ahri, role: .top, runeMode: .fixed, fixedPage: fixedPage),
                ChampionOverride(champion: ahri, role: .middle, isFavorite: true),
            ], mySpells: [4, 12])

        #expect(try other.sentRunePage() as NSDictionary? == plain.sentRunePage() as NSDictionary?)
        #expect(try other.sentSpells() == plain.sentSpells())
        #expect(try other.sentItemSet() as NSDictionary? == plain.sentItemSet() as NSDictionary?)
        #expect(other.model.outcome?.origins == [:])
        #expect(other.model.outcome?.rows.map(\.isLowSample) == [true, false, true])
    }

    @Test func planLeavesTheAdaptedLoadoutWithoutAnOverride() {
        let general = Loadout(runes: nil, spells: nil, itemSet: nil, skillOrder: nil)
        let adapted = Loadout(
            runes: fixedPage, spells: teleportAndFlash, itemSet: fixedItems, skillOrder: nil)

        #expect(
            ImportModel.plan(
                general: general, adapted: adapted, override: nil, settings: ImportSettings())
                == ImportModel.Plan(loadout: adapted))
    }
}

/// §17 `import_log`: one entry per part, codes only.
@Suite(.timeLimit(.minutes(1)))
struct ImportLogTests {
    @Test func logsEachPartOfAnImport() async throws {
        let harness = try await importAhri(overrides: [ahriOverride(itemMode: .skip)])

        let log = await harness.store.log
        #expect(log.map(\.part) == [.runes, .spells, .items])
        #expect(log.map(\.outcome) == [.applied, .applied, .skipped])
        #expect(log.map(\.detail) == ["override", "override", "override"])
        #expect(log.allSatisfy { $0.champion == ahri && $0.game == nil })
    }

    @Test func logsWhyAPartWasSkippedOrFailed() async throws {
        let harness = try await importAhri(overrides: [], mySpells: [4, 14]) {
            $0.connection.serve(
                LCUEndpoint.gameflowSession.path,
                try ImportFixture.data("session-aram", in: "gameflow-lobby"))
            $0.connection.serve(LCUEndpoint.perkStyles.path, Data("[]".utf8))
        }

        let log = await harness.store.log
        #expect(log.map(\.outcome) == [.failed, .skipped, .skipped])
        #expect(log.map(\.detail) == ["invalid_rune_page", "already_selected", "unsupported_map"])
    }

    @Test func aConfirmedReplacementLogsTheRunesAgain() async throws {
        let harness = try await importAhri(overrides: []) {
            $0.connection.serve(
                LCUEndpoint.perkInventory.path,
                try ImportFixture.data("inventory-full", in: "runes"))
        }
        #expect(await harness.store.log.first?.detail == "needs_confirmation")

        await harness.model.confirmReplacement()

        let last = try #require(await harness.store.log.last)
        #expect(last.part == .runes)
        #expect(last.outcome == .applied)
        #expect(await harness.store.log.count == 4)
    }
}

/// §13.3 and §21.4: `auto` takes the slot detected from the history.
@Suite(.timeLimit(.minutes(1)))
struct ImportDetectedFlashTests {
    @Test func autoUsesTheDetectedSlotOverTheSession() async throws {
        // The session holds Flash on D, but the history says F.
        let harness = try await importAhri(overrides: [], detectedFlash: .f, mySpells: [4, 12])

        #expect(try harness.sentSpells() == ["spell1Id": 14, "spell2Id": 4])
    }

    @Test func withNothingDetectedAutoFollowsTheSession() async throws {
        let harness = try await importAhri(overrides: [], detectedFlash: nil, mySpells: [12, 4])

        #expect(try harness.sentSpells() == ["spell1Id": 14, "spell2Id": 4])
    }

    @Test func aChosenSlotIgnoresTheDetection() async throws {
        let harness = try await importAhri(
            settings: ImportSettings(flashPosition: .d), overrides: [], detectedFlash: .f,
            mySpells: [12, 4])

        #expect(try harness.sentSpells() == ["spell1Id": 4, "spell2Id": 14])
    }
}

/// The §13.1 paths the trigger, override, and log suites above leave out.
@Suite(.timeLimit(.minutes(1)))
struct ImportEdgeTests {
    @Test func aDisconnectDropsTheConfirmationAndTheNextChampSelectAsksAgain() async throws {
        let harness = try Harness(windowInFront: true)
        harness.connection.serve(
            LCUEndpoint.perkInventory.path, try ImportFixture.data("inventory-full", in: "runes"))
        let run = harness.start()
        harness.connection.emit(try ImportFixture.lockedSession())
        await waitUntil { harness.model.outcome?.needsConfirmation == true }

        harness.connection.enter(.searching)
        await waitUntil { harness.model.outcome == nil }
        await harness.model.confirmReplacement()
        harness.connection.emit(try ImportFixture.lockedSession())
        await harness.stop(run)

        #expect(harness.runePageWrites().isEmpty)
        #expect(harness.model.outcome?.needsConfirmation == true)
    }

    @Test func anUndecodableSessionIsSkippedAndTheNextOneImports() async throws {
        let harness = try Harness()
        let run = harness.start()

        harness.connection.emit(Data(#""not a session""#.utf8))
        harness.connection.emit(try ImportFixture.lockedSession())
        await harness.stop(run)

        #expect(
            harness.poster.posts.map(\.notification) == [
                .loadoutImported(champion: ahri, opponent: nil)
            ])
    }

    @Test func aHoverThenALockOfAnotherChampionImportsBoth() async throws {
        let harness = try Harness(settings: ImportSettings(importOnHover: true))
        let run = harness.start()

        harness.connection.emit(try ImportFixture.data("ban-pick-in-progress"))
        harness.connection.emit(try ImportFixture.lockedSession(champion: 238))
        await harness.stop(run)

        #expect(
            harness.poster.posts.map(\.notification) == [
                .loadoutImported(champion: ahri, opponent: nil),
                .loadoutImported(champion: zed, opponent: nil),
            ])
    }

    @Test func anOlderToastsTimeoutLeavesTheNewerToast() async throws {
        let harness = try Harness(
            settings: ImportSettings(importOnHover: true), windowInFront: true)
        let run = harness.start()
        harness.connection.emit(try ImportFixture.data("ban-pick-in-progress"))
        await waitUntil { harness.model.outcome != nil }
        let first = try #require(harness.model.outcome?.id)
        harness.connection.emit(try ImportFixture.lockedSession(champion: 238))
        await harness.stop(run)

        harness.model.dismiss(first)

        #expect(harness.model.outcome?.champion == zed)
    }

    @Test func everyPartSkippedTellsNothingWithTheWindowClosed() async throws {
        let harness = try Harness(
            settings: ImportSettings(importRunes: false, importSpells: false, importItemSets: false)
        )
        let run = harness.start()

        harness.connection.emit(try ImportFixture.lockedSession())
        await harness.stop(run)

        #expect(harness.poster.posts.isEmpty)
        #expect(harness.model.outcome == nil)
    }

    @Test func withoutASnapshotNothingIsLogged() async throws {
        let harness = try Harness(stats: NoStats())
        let run = harness.start()

        harness.connection.emit(try ImportFixture.lockedSession())
        await harness.stop(run)

        #expect(harness.poster.posts.count == 1)
        #expect(await harness.store.log.isEmpty)
    }

    /// No override can be read and no log entry written: the general loadout still goes.
    @Test func anUnavailableStoreStillImportsTheGeneralLoadout() async throws {
        let harness = try Harness(windowInFront: true, personal: UnavailablePersonalStore())
        let run = harness.start()

        harness.connection.emit(try ImportFixture.lockedSession(mySpells: [4, 12]))
        await harness.stop(run)

        #expect(try harness.sentRunePage()?["primaryStyleId"] as? Int == 8200)
        #expect(try harness.sentSpells() == ["spell1Id": 4, "spell2Id": 14])
        #expect(harness.connection.writes(.put, itemSetsPath).count == 1)
        let outcome = try #require(harness.model.outcome)
        #expect(outcome.status == .imported)
        #expect(outcome.origins.isEmpty)
    }

    @Test func anUnreadableGameflowSessionSkipsTheItems() async throws {
        let harness = try Harness(windowInFront: true)
        harness.connection.serve(LCUEndpoint.gameflowSession.path, Data("not json".utf8))
        let run = harness.start()

        harness.connection.emit(try ImportFixture.lockedSession())
        await harness.stop(run)

        #expect(harness.model.outcome?.itemsUnavailable == .unsupportedMap)
        #expect(harness.model.outcome?.report.runes == .applied)
        #expect(!harness.connection.requests.contains { $0.path.hasPrefix("/lol-item-sets") })
    }

    @Test func withoutTheClientCatalogTheTitleUsesTheChampionID() async throws {
        let harness = try Harness(windowInFront: true, servesGameData: false)
        let run = harness.start()

        harness.connection.emit(try ImportFixture.lockedSession())
        await harness.stop(run)

        #expect(harness.model.outcome?.title == "103 MID")
        #expect(try harness.sentRunePage()?["name"] as? String == "Mito · 103 MID")
    }
}

/// §13.1: a fixed mode with nothing saved, and modes this build does not know.
@Suite(.timeLimit(.minutes(1)))
struct ImportOverrideFallbackTests {
    @Test func fixedSpellsAndItemsWithNothingSavedSendTheGeneralOnesAndSaySo() async throws {
        let harness = try await importAhri(
            overrides: [ahriOverride(runeMode: .general, spells: nil, items: nil)],
            mySpells: [4, 12])

        #expect(try harness.sentSpells() == ["spell1Id": 4, "spell2Id": 14])
        let blocks = try #require(try harness.sentItemSet()?["blocks"] as? [[String: Any]])
        #expect(blocks.first?["type"] as? String == "Inicio")
        let outcome = try #require(harness.model.outcome)
        #expect(outcome.origins == [.spells: .noFixedChoice, .items: .noFixedChoice])
        #expect(outcome.rows.map(\.origin) == [nil, .noFixedChoice, .noFixedChoice])
        #expect(
            await harness.store.log.map(\.detail) == [nil, "no_fixed_choice", "no_fixed_choice"])
    }

    @Test func unknownSpellAndItemModesFollowTheEngine() async throws {
        let harness = try await importAhri(
            overrides: [
                ahriOverride(
                    runeMode: .general, spellMode: .unknown("swap_v2"),
                    itemMode: .unknown("situational_v2"))
            ], mySpells: [4, 12])

        #expect(try harness.sentSpells() == ["spell1Id": 4, "spell2Id": 14])
        let blocks = try #require(try harness.sentItemSet()?["blocks"] as? [[String: Any]])
        #expect(blocks.first?["type"] as? String == "Inicio")
        #expect(harness.model.outcome?.origins == [:])
    }
}

private let darius = 122
private let soraka = 16
private let leeSin = 64
private let ashe = 22

/// Zed assigned MIDDLE; Darius TOP, Lee Sin JUNGLE, Ashe BOTTOM and Soraka UTILITY by inference
/// make a heavy_ad and heavy_cc team, with two `high_heal` enemies.
private let zedInAHeavyADTeam: [(champion: Int, position: String)] = [
    (238, "middle"), (darius, ""), (soraka, ""), (leeSin, ""), (ashe, ""),
]
/// Darius TOP, Lee Sin JUNGLE, Ashe BOTTOM: heavy_ad and heavy_cc, nobody in MIDDLE.
private let heavyADWithoutAMid: [(champion: Int, position: String)] = [
    (darius, ""), (leeSin, ""), (ashe, ""),
]
/// Darius TOP, Soraka UTILITY, Ashe BOTTOM: mixed and heavy_cc, nobody in MIDDLE.
private let mixedWithoutAMid: [(champion: Int, position: String)] = [
    (darius, ""), (soraka, ""), (ashe, ""),
]

private let phaseRushPerks = [8229, 8226, 8210, 8237, 8304, 8347, 5007, 5008, 5011]
private let electrocutePerks = [8112, 8143, 8140, 8135, 8345, 8347, 5008, 5008, 5011]

/// One locked Ahri MID import against `enemies`, with the window in front.
private func importAhri(
    against enemies: [(champion: Int, position: String)],
    settings: ImportSettings = ImportSettings(), overrides: [ChampionOverride] = [],
    windowInFront: Bool = true
) async throws -> Harness {
    let harness = try Harness(
        settings: settings, windowInFront: windowInFront, overrides: overrides)
    let run = harness.start()
    harness.connection.emit(
        try ImportFixture.lockedSession(mySpells: [4, 12], enemies: enemies))
    await harness.stop(run)
    return harness
}

extension Harness {
    fileprivate func sentBlocks() throws -> [(title: String?, items: [String])] {
        let blocks = try #require(try sentItemSet()?["blocks"] as? [[String: Any]])
        return blocks.map { block in
            (
                block["type"] as? String,
                (block["items"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
            )
        }
    }

    fileprivate var markers: [String?] {
        model.outcome?.rows.map(\.adaptationMarker) ?? []
    }
}

/// §13.1 and §18.6–§18.8: the import sends the loadout adapted to the lane opponent and the
/// enemy team.
@Suite(.timeLimit(.minutes(1)))
struct ImportAdaptedLoadoutTests {
    @Test func aKnownLaneOpponentSendsTheLoadoutAdaptedToIt() async throws {
        let harness = try await importAhri(against: zedInAHeavyADTeam)

        // Against Zed the page, the pair, start, core and boots come from his rows: the same
        // content as the general ones in the fixture, so the markers tell them apart.
        #expect(try harness.sentRunePage()?["selectedPerkIds"] as? [Int] == phaseRushPerks)
        #expect(try harness.sentSpells() == ["spell1Id": 4, "spell2Id": 14])
        let blocks = try harness.sentBlocks()
        #expect(
            blocks.map(\.title) == [
                "Inicio", "Núcleo", "Botas", "4.º ítem", "5.º ítem", "Situacionales",
            ])
        #expect(blocks[2].items == ["3020"])
        // Darius and Soraka heal: Morellonomicon.
        #expect(blocks.last?.items == ["3165"])
        #expect(
            harness.markers == [
                "· vs Zed", "· vs Zed", "· vs Zed · Morellonomicon: 2 rivales con curación alta",
            ])
        #expect(harness.model.outcome?.opponent == zed)
    }

    @Test func theNotificationNamesTheLaneOpponent() async throws {
        let harness = try await importAhri(against: zedInAHeavyADTeam, windowInFront: false)

        #expect(
            harness.poster.posts.map(\.notification) == [
                .loadoutImported(champion: ahri, opponent: zed)
            ])
    }

    @Test func aHeavyADTeamWithoutALaneOpponentSendsTheProfileRunesAndBoots() async throws {
        let harness = try await importAhri(against: heavyADWithoutAMid)

        #expect(try harness.sentRunePage()?["selectedPerkIds"] as? [Int] == phaseRushPerks)
        let blocks = try harness.sentBlocks()
        #expect(blocks.map(\.title) == ["Inicio", "Núcleo", "Botas", "4.º ítem", "5.º ítem"])
        // Plated Steelcaps rise 3× against heavy_ad.
        #expect(blocks[2].items == ["3047"])
        #expect(
            harness.markers == ["· vs mucho AD · vs mucho CC", nil, "· vs mucho AD"])
        #expect(harness.model.outcome?.opponent == nil)
    }

    @Test func aMixedTeamSendsTheProfilePageOverTheGeneralOne() async throws {
        let harness = try await importAhri(against: mixedWithoutAMid)

        // Electrocute wins over mixed and heavy_cc; the general page is Phase Rush.
        #expect(try harness.sentRunePage()?["selectedPerkIds"] as? [Int] == electrocutePerks)
        #expect(
            harness.markers == [
                "· vs mucho CC · vs daño mixto", nil,
                "· Morellonomicon: 2 rivales con curación alta",
            ])
    }

    @Test func anOpponentInferredAtEvenOddsOrBetterCounts() async throws {
        // Lee Sin plays only JUNGLE, which leaves Zed MIDDLE.
        let harness = try await importAhri(against: [(238, ""), (leeSin, "")])

        #expect(harness.model.outcome?.opponent == zed)
        #expect(harness.markers.first == "· vs Zed")
    }

    @Test func anOpponentInferredBelowEvenOddsIsIgnored() async throws {
        // Zed alone: 2,195 MIDDLE games of 4,941, 44 %.
        let harness = try await importAhri(against: [(238, "")])

        #expect(harness.model.outcome?.opponent == nil)
        #expect(harness.markers == [nil, nil, nil])
        #expect(try harness.sentBlocks().map(\.title).last == "5.º ítem")
    }

    @Test func noLockedEnemySendsTheGeneralLoadout() async throws {
        let harness = try await importAhri(against: [])

        #expect(try harness.sentRunePage()?["selectedPerkIds"] as? [Int] == phaseRushPerks)
        #expect(try harness.sentBlocks().map(\.items)[2] == ["3020"])
        #expect(harness.markers == [nil, nil, nil])
    }

    @Test func aPartLeftOutCarriesNoMarker() async throws {
        let harness = try await importAhri(
            against: zedInAHeavyADTeam, settings: ImportSettings(importRunes: false))

        #expect(
            harness.markers == [
                nil, "· vs Zed", "· vs Zed · Morellonomicon: 2 rivales con curación alta",
            ])
    }

    @Test func withoutASnapshotNothingIsImportedWhateverTheEnemies() async throws {
        let harness = try Harness(windowInFront: true, stats: NoStats())
        let run = harness.start()
        harness.connection.emit(
            try ImportFixture.lockedSession(enemies: zedInAHeavyADTeam))
        await harness.stop(run)

        #expect(harness.writes.isEmpty)
        #expect(harness.model.outcome?.status == .noStats)
    }
}

/// §13.1 and §21.5: overrides keep their precedence over the adapted loadout.
@Suite(.timeLimit(.minutes(1)))
struct ImportAdaptedOverrideTests {
    @Test func fixedChoicesBeatTheAdaptedOnes() async throws {
        let harness = try await importAhri(
            against: zedInAHeavyADTeam, overrides: [ahriOverride()])

        #expect(try harness.sentRunePage()?["primaryStyleId"] as? Int == 8100)
        // Teleport + Flash, which the player already holds, instead of Ignite against Zed.
        #expect(harness.model.outcome?.report.spells == .skipped(.alreadySelected))
        #expect(try harness.sentBlocks().map(\.title) == ["Mi set"])
        #expect(
            harness.model.outcome?.origins == [
                .runes: .override, .spells: .override, .items: .override,
            ])
        #expect(harness.markers == [nil, nil, nil])
    }

    @Test func aGeneralRuneOverrideSendsTheGeneralPage() async throws {
        let harness = try await importAhri(
            against: mixedWithoutAMid,
            overrides: [
                ahriOverride(runeMode: .general, spellMode: .recommended, itemMode: .recommended)
            ])

        #expect(try harness.sentRunePage()?["selectedPerkIds"] as? [Int] == phaseRushPerks)
        #expect(harness.markers.first == .some(nil))
        // Only the runes go general.
        #expect(harness.markers.last == "· Morellonomicon: 2 rivales con curación alta")
    }

    @Test func theGeneralGlobalModeSendsTheGeneralPage() async throws {
        let harness = try await importAhri(
            against: mixedWithoutAMid, settings: ImportSettings(runeMode: .general),
            overrides: [ahriOverride(runeMode: .adaptive)])

        #expect(try harness.sentRunePage()?["selectedPerkIds"] as? [Int] == phaseRushPerks)
        #expect(harness.model.outcome?.origins[.runes] == nil)
    }

    @Test func anAdaptiveOverrideUnderTheAdaptiveGlobalModeSendsTheAdaptedPage() async throws {
        let harness = try await importAhri(
            against: mixedWithoutAMid, overrides: [ahriOverride(runeMode: .adaptive)])

        #expect(try harness.sentRunePage()?["selectedPerkIds"] as? [Int] == electrocutePerks)
        #expect(harness.markers.first == "· vs mucho CC · vs daño mixto")
    }

    @Test func aFixedModeWithNothingSavedSendsTheGeneralPart() async throws {
        let harness = try await importAhri(
            against: zedInAHeavyADTeam,
            overrides: [ahriOverride(runeMode: .fixed, page: nil, spells: nil, items: nil)])

        let blocks = try harness.sentBlocks()
        #expect(blocks.map(\.title) == ["Inicio", "Núcleo", "Botas", "4.º ítem", "5.º ítem"])
        #expect(
            harness.model.outcome?.origins
                == [.runes: .noFixedChoice, .spells: .noFixedChoice, .items: .noFixedChoice])
        #expect(harness.markers == [nil, nil, nil])
    }
}

/// §12.3: the lane opponent of the local player's role.
struct ImportLaneOpponentTests {
    private func slot(_ cell: Int, _ champion: Int?, _ role: Role? = nil) -> DraftSlot {
        DraftSlot(
            cellId: cell, champion: champion.map(ChampionID.init(rawValue:)), hover: nil,
            role: role, roleConfidence: role == nil ? 0 : 1)
    }

    @Test func theEnemyAssignedToTheRoleIsTheOpponent() throws {
        let stats = try SnapshotFixture.reader()

        #expect(
            ImportModel.laneOpponent(
                among: [slot(5, darius), slot(6, 238, .middle)], in: .middle, stats: stats) == zed)
    }

    @Test func aRoleHeldByAnEnemyStillPickingHasNoOpponent() throws {
        let stats = try SnapshotFixture.reader()

        #expect(
            ImportModel.laneOpponent(
                among: [slot(5, 238), slot(6, nil, .middle)], in: .middle, stats: stats) == nil)
    }

    @Test func theLikeliestEnemyCountsFromEvenOdds() throws {
        let stats = try SnapshotFixture.reader()

        // Zed: 56 % JUNGLE, 44 % MIDDLE.
        #expect(ImportModel.laneOpponent(among: [slot(5, 238)], in: .jungle, stats: stats) == zed)
        #expect(ImportModel.laneOpponent(among: [slot(5, 238)], in: .middle, stats: stats) == nil)
    }
}

/// §13.4: the engine's `situational` block gets its copy.
@Suite(.timeLimit(.minutes(1)))
struct ImportBlockTitleTests {
    @Test func theSituationalBlockIsTitledSituacionales() async throws {
        let harness = try await importAhri(against: zedInAHeavyADTeam)

        #expect(try harness.sentBlocks().last?.title == "Situacionales")
    }
}
