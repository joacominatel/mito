import Foundation
import MitoAssets
import MitoCore
import Testing

@testable import Mito

private typealias Fixture = OnboardingFixture

private func model(_ store: PoolTestStore, role: Role = .middle) -> OnboardingModel {
    let model = OnboardingModel(store: store)
    model.role = role
    return model
}

struct OnboardingPoolTests {
    @Test func loadsTheRolesPoolInPriorityOrder() async {
        let store = PoolTestStore(pools: [.middle: [Fixture.zed, Fixture.ahri]])
        let model = model(store)

        await model.loadPool()

        #expect(model.pool == [Fixture.zed, Fixture.ahri])
        #expect(model.poolProblem == nil)
    }

    @Test func anotherRoleLoadsItsOwnPool() async {
        let store = PoolTestStore(pools: [.middle: [Fixture.ahri], .top: [Fixture.annie]])
        let model = model(store)
        await model.loadPool()

        model.role = .top
        await model.loadPool()

        #expect(model.pool == [Fixture.annie])
    }

    @Test func addingAppendsAndSavesTheWholePoolInOrder() async {
        let store = PoolTestStore(pools: [.middle: [Fixture.ahri]])
        let model = model(store)
        await model.loadPool()

        await model.add(Fixture.zed)

        #expect(model.pool == [Fixture.ahri, Fixture.zed])
        #expect(await store.stored(.middle) == [Fixture.ahri, Fixture.zed])
    }

    @Test func addingAChampionAlreadyInThePoolSavesNothing() async {
        let store = PoolTestStore(pools: [.middle: [Fixture.ahri]])
        let model = model(store)
        await model.loadPool()

        await model.add(Fixture.ahri)

        #expect(await store.saved.isEmpty)
    }

    @Test func removingSavesThePoolWithoutIt() async {
        let store = PoolTestStore(pools: [.middle: [Fixture.ahri, Fixture.zed, Fixture.annie]])
        let model = model(store)
        await model.loadPool()

        await model.remove(Fixture.zed)

        #expect(model.pool == [Fixture.ahri, Fixture.annie])
        #expect(await store.stored(.middle) == [Fixture.ahri, Fixture.annie])
    }

    @Test func movingUpAndDownSavesTheNewOrder() async {
        let store = PoolTestStore(pools: [.middle: [Fixture.ahri, Fixture.zed, Fixture.annie]])
        let model = model(store)
        await model.loadPool()

        await model.moveUp(Fixture.annie)
        #expect(await store.stored(.middle) == [Fixture.ahri, Fixture.annie, Fixture.zed])

        await model.moveDown(Fixture.ahri)
        #expect(await store.stored(.middle) == [Fixture.annie, Fixture.ahri, Fixture.zed])
        #expect(model.pool.first == Fixture.annie)
    }

    @Test func movingPastEitherEndSavesNothing() async {
        let store = PoolTestStore(pools: [.middle: [Fixture.ahri, Fixture.zed]])
        let model = model(store)
        await model.loadPool()

        await model.moveUp(Fixture.ahri)
        await model.moveDown(Fixture.zed)

        #expect(await store.saved.isEmpty)
        #expect(model.pool == [Fixture.ahri, Fixture.zed])
    }

    @Test func aFailedSaveUndoesTheChangeAndSaysSo() async {
        let store = PoolTestStore(pools: [.middle: [Fixture.ahri]])
        let model = model(store)
        await model.loadPool()
        await store.failWrites()

        await model.add(Fixture.zed)

        #expect(model.pool == [Fixture.ahri])
        #expect(model.poolProblem == .saveFailed)
        #expect(model.canEditPool)
    }

    @Test func anUnreadablePoolTurnsEditingOff() async {
        let store = PoolTestStore(failsReads: true)
        let model = model(store)

        await model.loadPool()
        await model.add(Fixture.ahri)

        #expect(model.poolProblem == .readFailed)
        #expect(!model.canEditPool)
        #expect(model.pool.isEmpty)
        #expect(await store.saved.isEmpty)
    }
}

struct OnboardingCatalogTests {
    @Test func theSharedChampionsAreListedByNameWithoutThePlaceholder() {
        let model = OnboardingModel(store: PoolTestStore(), gameData: Fixture.gameData)

        #expect(model.searchResults.map(\.name) == ["Ahri", "Annie"])
        #expect(model.name(of: Fixture.ahri) == "Ahri")
        #expect(model.canAddToPool)
    }

    @Test func searchSkipsThePoolAndMatchesTheName() async {
        let store = PoolTestStore(pools: [.middle: [Fixture.ahri]])
        let model = OnboardingModel(store: store, gameData: Fixture.gameData)
        model.role = .middle
        await model.loadPool()

        #expect(model.searchResults.map(\.id) == [Fixture.annie])

        model.query = "ahr"
        #expect(model.searchResults.isEmpty)

        model.query = "ANN"
        #expect(model.searchResults.map(\.id) == [Fixture.annie])
    }

    @Test func theListFollowsTheSharedDataOnceItLoads() {
        var shared: GameData?
        let model = OnboardingModel(store: PoolTestStore(), gameData: shared)
        #expect(model.catalog == .unavailable)

        shared = Fixture.gameData

        #expect(model.searchResults.map(\.name) == ["Ahri", "Annie"])
    }

    @Test func withoutClientDataNothingCanBeAdded() async {
        let model = model(PoolTestStore(pools: [.middle: [Fixture.ahri]]))

        await model.loadPool()

        #expect(model.catalog == .unavailable)
        #expect(!model.canAddToPool)
        #expect(model.canEditPool)
        #expect(model.name(of: Fixture.ahri) == "Campeón 103")
    }
}

struct OnboardingFlashTests {
    @Test func runDetectsTheSlotWithoutTheTabOpen() async {
        let model = model(PoolTestStore(history: Fixture.history(d: 1, f: 6)))

        await model.run()

        #expect(model.flash == .loaded(.init(inD: 1, inF: 6)))
        #expect(model.resolvedFlashSlot(.auto) == .f)
    }

    @Test func countsFlashBySlotOverTheLast20Games() async {
        let store = PoolTestStore(history: Fixture.history(d: 2, f: 18, without: 5))
        let model = model(store)

        await model.detectFlash()

        #expect(model.flash == .loaded(.init(inD: 2, inF: 18)))
        #expect(await store.lastQuery?.limit == 20)
        #expect(String(localized: model.flashSummary) == "Detectado: F en 18 de 20 partidas")
    }

    @Test func gamesWithoutFlashAreNotCounted() async {
        let model = model(PoolTestStore(history: Fixture.history(d: 3, f: 1, without: 4)))

        await model.detectFlash()

        #expect(model.flash == .loaded(.init(inD: 3, inF: 1)))
        #expect(model.resolvedFlashSlot(.auto) == .d)
    }

    @Test func noHistoryDetectsNothing() async {
        let model = model(PoolTestStore())

        await model.detectFlash()

        #expect(model.flash == .loaded(.init(inD: 0, inF: 0)))
        #expect(model.resolvedFlashSlot(.auto) == nil)
        #expect(String(localized: model.flashSummary) == "Sin partidas con Flash en tu historial")
    }

    @Test func aTieHasNoMajority() async {
        let model = model(PoolTestStore(history: Fixture.history(d: 4, f: 4)))

        await model.detectFlash()

        #expect(model.resolvedFlashSlot(.auto) == nil)
    }

    @Test func autoFollowsTheMajorityAndAFixedSlotIgnoresIt() async {
        let model = model(PoolTestStore(history: Fixture.history(d: 1, f: 6)))

        await model.detectFlash()

        #expect(model.resolvedFlashSlot(.auto) == .f)
        #expect(model.resolvedFlashSlot(.d) == .d)
        #expect(model.resolvedFlashSlot(.f) == .f)
    }

    @Test func anUnreadableHistoryLeavesAutoUnresolved() async {
        let model = model(PoolTestStore(failsReads: true))

        await model.detectFlash()

        #expect(model.flash == .unavailable)
        #expect(model.resolvedFlashSlot(.auto) == nil)
        #expect(model.resolvedFlashSlot(.d) == .d)
    }
}

struct OnboardingFlashSummaryTests {
    @Test(
        arguments: [
            (5, 2, "Detectado: D en 5 de 7 partidas"),
            (3, 3, "Empate: D y F en 3 partidas cada una"),
        ])
    func theSummaryNamesTheMajorityOrTheTie(d: Int, f: Int, summary: String) async {
        let model = model(PoolTestStore(history: Fixture.history(d: d, f: f)))

        await model.detectFlash()

        #expect(String(localized: model.flashSummary) == summary)
    }

    @Test func theSummarySaysWhenTheHistoryIsUnreadableOrStillLoading() async {
        let model = model(PoolTestStore(failsReads: true))
        #expect(String(localized: model.flashSummary) == "Leyendo tus partidas…")

        await model.detectFlash()

        #expect(String(localized: model.flashSummary) == "No se pudo leer tu historial")
    }
}
