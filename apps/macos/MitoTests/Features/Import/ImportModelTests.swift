import Foundation
import LCUKit
import MitoCore
import MitoImport
import Testing

@testable import Mito

private let ahri = ChampionID(rawValue: 103)
private let mySelectionPath = "/lol-champ-select/v1/session/my-selection"
private let pagesPath = LCUEndpoint.perkPages.path
private let itemSetsPath = LCUEndpoint.itemSets(summonerId: 1).path

/// One model over a scripted connection that serves the recorded cases, and a recording poster.
private struct Harness {
    let connection = ImportTestConnection()
    let poster = RecordingPoster()
    let model: ImportModel

    init(settings: ImportSettings = ImportSettings(), windowInFront: Bool = false) throws {
        model = ImportModel(
            connection: connection, settings: { settings }, poster: poster, appIsActive: { true })
        if windowInFront { model.windowAppeared() }
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

        let body = try #require(harness.connection.writes(.patch, mySelectionPath).first?.body)
        let sent = try JSONSerialization.jsonObject(with: body) as? [String: Int]
        #expect(sent == ["spell1Id": 4, "spell2Id": 14])
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

    @Test func aChampionWithoutABuildImportsNothing() async throws {
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
        let model = ImportModel(connection: connection, poster: poster, appIsActive: { false })
        model.windowAppeared()

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
        let model = ImportModel(connection: connection)

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
