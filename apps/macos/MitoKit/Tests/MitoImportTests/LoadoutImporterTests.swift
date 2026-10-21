import Foundation
import LCUKit
import MitoCore
import MitoImport
import MitoTestSupport
import Synchronization
import Testing

private let pagesPath = "/lol-perks/v1/pages"
private let mySelectionPath = "/lol-champ-select/v1/session/my-selection"
private let setsPath = "/lol-item-sets/v1/item-sets/42/sets"
private let runeWrite = "POST \(pagesPath)"
private let spellWrite = "PATCH \(mySelectionPath)"
private let itemSetWrite = "PUT \(setsPath)"

/// Electrocute, Taste of Blood, Grisly Mementos, Ultimate Hunter; Manaflow Band, Transcendence;
/// adaptive, adaptive, health scaling.
private let validPerks = [8112, 8139, 8140, 8135, 8226, 8210, 5008, 5008, 5001]

private func runePage(_ perks: [Int] = validPerks) -> RunePage {
    RunePage(
        primaryStyle: PerkStyleID(rawValue: 8100), subStyle: PerkStyleID(rawValue: 8200),
        perks: perks.map(PerkID.init))
}

private let flashIgnite = SpellPair(
    first: SummonerSpellID(rawValue: 4), second: SummonerSpellID(rawValue: 14))

private let itemSet = ItemSet(blocks: [
    .init(title: "Inicio", items: [.init(id: ItemID(rawValue: 1056))])
])

private func loadout(
    runes: RunePage? = runePage(), spells: SpellPair? = flashIgnite, itemSet: ItemSet? = itemSet
) -> Loadout {
    Loadout(runes: runes, spells: spells, itemSet: itemSet, skillOrder: nil)
}

private func context(
    title: String = "Ahri MID vs Zed", session: ChampSelectSession = .init(),
    confirmedReplacement: Int? = nil
) -> LoadoutImportContext {
    LoadoutImportContext(
        title: title, champion: ChampionID(rawValue: 103), session: session, summonerId: 42,
        confirmedReplacement: confirmedReplacement)
}

private func runesCase(_ name: String) throws -> Data {
    try Data(contentsOf: Fixtures.url("lcu/cases/runes/\(name).json"))
}

/// A client where all three importers can write; `inventory-full` leaves no free rune page.
private func connection(
    inventory: String = "inventory-with-room", runeWriteStatus: Int = 200
) throws -> FakeLCUConnection {
    FakeLCUConnection(responses: [
        .init(method: .get, path: "/lol-perks/v1/styles", body: try runesCase("styles")),
        .init(method: .get, path: pagesPath, body: try runesCase("pages-without-mito-page")),
        .init(method: .get, path: "/lol-perks/v1/inventory", body: try runesCase(inventory)),
        .init(method: .post, path: pagesPath, status: runeWriteStatus),
        .init(method: .put, path: "\(pagesPath)/201"),
        .init(method: .patch, path: mySelectionPath, status: 204),
        .init(
            method: .get, path: setsPath,
            body: try Data(contentsOf: Fixtures.url("lcu/cases/item-sets/empty.json"))),
        .init(method: .put, path: setsPath, status: 204),
    ])
}

private func writeRoutes(_ connection: FakeLCUConnection) -> [String] {
    connection.writes.map { "\($0.method.rawValue) \($0.path)" }
}

private let applied = ImportReport(runes: .applied, spells: .applied, items: .applied)

struct LoadoutImporterTests {
    @Test func appliesAFullLoadoutWritingRunesThenSpellsThenItems() async throws {
        let lcu = try connection()
        let report = await LoadoutImporter(connection: lcu).apply(
            loadout(), settings: ImportSettings(), context: context())

        #expect(report == applied)
        #expect(writeRoutes(lcu) == [runeWrite, spellWrite, itemSetWrite])
    }

    @Test func aMissingPartIsSkippedWithoutTouchingTheClient() async throws {
        let lcu = try connection()
        let report = await LoadoutImporter(connection: lcu).apply(
            loadout(runes: nil), settings: ImportSettings(), context: context())

        #expect(report.runes == .skipped(.notInLoadout))
        #expect(!lcu.requests.contains { $0.path.hasPrefix("/lol-perks/") })
        #expect(writeRoutes(lcu) == [spellWrite, itemSetWrite])
    }

    @Test func aFailedStepDoesNotStopTheOthers() async throws {
        let lcu = try connection(runeWriteStatus: 500)
        let report = await LoadoutImporter(connection: lcu).apply(
            loadout(), settings: ImportSettings(), context: context())

        #expect(report.runes == .failed(.lcu(.http(status: 500, body: Data()))))
        #expect(report.spells == .applied)
        #expect(report.items == .applied)
        #expect(writeRoutes(lcu) == [runeWrite, spellWrite, itemSetWrite])
    }

    @Test func spellAndItemSetFailuresAreReportedAsLCUFailures() async throws {
        let lcu = FakeLCUConnection(responses: [
            .init(method: .patch, path: mySelectionPath, status: 500),
            .init(method: .get, path: setsPath, status: 503),
        ])
        let report = await LoadoutImporter(connection: lcu).apply(
            loadout(runes: nil), settings: ImportSettings(), context: context())

        #expect(report.spells == .failed(.lcu(.http(status: 500, body: Data()))))
        #expect(report.items == .failed(.lcu(.http(status: 503, body: Data()))))
        #expect(writeRoutes(lcu) == [spellWrite])
    }

    @Test func everyStepIsSkippedAndNothingSentWhenEveryImportIsOff() async throws {
        let lcu = try connection()
        let settings = ImportSettings(
            importRunes: false, importSpells: false, importItemSets: false)
        let report = await LoadoutImporter(connection: lcu).apply(
            loadout(), settings: settings, context: context())

        #expect(
            report
                == ImportReport(
                    runes: .skipped(.disabled), spells: .skipped(.disabled),
                    items: .skipped(.disabled)))
        #expect(lcu.requests.isEmpty)
    }

    @Test func aRunePageThatNeedsConfirmationIsReportedWithThePageToReplace() async throws {
        let lcu = try connection(inventory: "inventory-full")
        let report = await LoadoutImporter(connection: lcu).apply(
            loadout(), settings: ImportSettings(), context: context())

        #expect(report.runes == .needsConfirmation(pageID: 201, pageName: "My page"))
        #expect(writeRoutes(lcu) == [spellWrite, itemSetWrite])
    }

    @Test func aConfirmedReplacementOverwritesThatPage() async throws {
        let lcu = try connection(inventory: "inventory-full")
        let report = await LoadoutImporter(connection: lcu).apply(
            loadout(), settings: ImportSettings(), context: context(confirmedReplacement: 201))

        #expect(report == applied)
        #expect(writeRoutes(lcu) == ["PUT \(pagesPath)/201", spellWrite, itemSetWrite])
    }

    @Test func anInvalidRunePageIsReportedWithItsValidationError() async throws {
        let lcu = try connection()
        let report = await LoadoutImporter(connection: lcu).apply(
            loadout(runes: runePage(Array(validPerks.dropLast()))), settings: ImportSettings(),
            context: context())

        #expect(report.runes == .failed(.invalidRunePage(.wrongPerkCount(8))))
        #expect(writeRoutes(lcu) == [spellWrite, itemSetWrite])
    }

    @Test func aRuneTargetThatCannotBeEditedIsSkipped() async throws {
        let lcu = try connection()
        let settings = ImportSettings(runePageTarget: .reservedPage, reservedRunePageID: nil)
        let report = await LoadoutImporter(connection: lcu).apply(
            loadout(), settings: settings, context: context())

        #expect(report.runes == .skipped(.noEditablePage))
    }

    @Test func spellsThatAreAlreadySelectedAreSkipped() async throws {
        let me = ChampSelectSession.Member(
            cellId: 2, spell1Id: flashIgnite.first, spell2Id: flashIgnite.second)
        let session = ChampSelectSession(localPlayerCellId: 2, myTeam: [me])
        let lcu = try connection()
        let report = await LoadoutImporter(connection: lcu).apply(
            loadout(), settings: ImportSettings(), context: context(session: session))

        #expect(report.spells == .skipped(.alreadySelected))
        #expect(writeRoutes(lcu) == [runeWrite, itemSetWrite])
    }

    @Test func overlappingAppliesRunOneAfterTheOther() async throws {
        let lcu = try connection()
        let gated = GatedConnection(lcu)
        let importer = LoadoutImporter(connection: gated)

        let first = Task {
            await importer.apply(
                loadout(), settings: ImportSettings(), context: context(title: "1"))
        }
        var held = gated.held.makeAsyncIterator()
        await held.next()
        let second = Task {
            await importer.apply(
                loadout(), settings: ImportSettings(), context: context(title: "2"))
        }
        // Gives the second apply every chance to reach the client while the first is held.
        for _ in 0..<200 { await Task.yield() }
        gated.release()

        #expect(await first.value == applied)
        #expect(await second.value == applied)
        #expect(
            writeRoutes(lcu) == [
                runeWrite, spellWrite, itemSetWrite, runeWrite, spellWrite, itemSetWrite,
            ])
        let runeNames = try lcu.writes.filter { $0.method == .post }.map { request in
            let body = try #require(request.body)
            let json = try #require(try JSONSerialization.jsonObject(with: body) as? NSDictionary)
            return try #require(json["name"] as? String)
        }
        #expect(runeNames == ["Mito · 1", "Mito · 2"])
    }
}

/// Holds the first request until `release()`, then forwards everything to `inner`.
private final class GatedConnection: LCUConnection {
    private struct State {
        var holding = true
        var waiter: CheckedContinuation<Void, Never>?
    }

    private let inner: FakeLCUConnection
    private let state = Mutex(State())
    private let heldContinuation: AsyncStream<Void>.Continuation
    /// Yields once the first request is being held.
    let held: AsyncStream<Void>

    init(_ inner: FakeLCUConnection) {
        self.inner = inner
        (held, heldContinuation) = AsyncStream.makeStream()
    }

    func send<R: Decodable & Sendable>(_ endpoint: LCUEndpoint<R>) async throws(LCUError) -> R {
        let hold = state.withLock { state in
            defer { state.holding = false }
            return state.holding
        }
        if hold {
            await withCheckedContinuation { continuation in
                state.withLock { $0.waiter = continuation }
                heldContinuation.yield()
            }
        }
        return try await inner.send(endpoint)
    }

    func release() {
        state.withLock { $0.waiter.take() }?.resume()
    }

    func events(_ topics: Set<LCUTopic>) -> AsyncStream<LCUEvent> { inner.events(topics) }

    func states() -> AsyncStream<ConnectionState> { inner.states() }
}
