import Foundation
import LCUKit
import MitoCore
import MitoImport
import MitoTestSupport
import Testing

private let mySelectionPath = "/lol-champ-select/v1/session/my-selection"
private let flash = 4
private let ignite = 14
private let teleport = 12
private let smite = 11

private func pair(_ first: Int, _ second: Int) -> SpellPair {
    SpellPair(first: SummonerSpellID(rawValue: first), second: SummonerSpellID(rawValue: second))
}

private func settings(
    _ flashPosition: ImportSettings.FlashPosition, importSpells: Bool = true
) -> ImportSettings {
    ImportSettings(importSpells: importSpells, flashPosition: flashPosition)
}

/// The local player is cell 2; a teammate in cell 0 holds Flash on D to catch a wrong lookup.
private func session(current: (Int, Int)?) -> ChampSelectSession {
    let teammate = ChampSelectSession.Member(
        cellId: 0, spell1Id: SummonerSpellID(rawValue: flash),
        spell2Id: SummonerSpellID(rawValue: ignite))
    guard let current else { return ChampSelectSession(myTeam: [teammate]) }
    let me = ChampSelectSession.Member(
        cellId: 2, spell1Id: SummonerSpellID(rawValue: current.0),
        spell2Id: SummonerSpellID(rawValue: current.1))
    return ChampSelectSession(localPlayerCellId: 2, myTeam: [teammate, me])
}

private func connection(status: Int = 204) -> FakeLCUConnection {
    FakeLCUConnection(responses: [.init(method: .patch, path: mySelectionPath, status: status)])
}

/// The spells of every PATCH sent, decoded from its body.
private func sentPairs(_ connection: FakeLCUConnection) throws -> [SpellPair] {
    try connection.writes.map { request in
        let body = try #require(request.body)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Int])
        return pair(try #require(json["spell1Id"]), try #require(json["spell2Id"]))
    }
}

private func apply(
    _ recommended: SpellPair, _ settings: ImportSettings, _ session: ChampSelectSession,
    on connection: FakeLCUConnection
) async -> SpellImportResult {
    await SpellImporter(connection: connection).apply(
        recommended, settings: settings, session: session)
}

private let flashInEitherSlot = [pair(flash, ignite), pair(ignite, flash)]

struct SpellImporterTests {
    @Test(arguments: flashInEitherSlot)
    func flashOnFAlwaysGoesInSpell2(_ recommended: SpellPair) async throws {
        let lcu = connection()
        let result = await apply(recommended, settings(.f), session(current: nil), on: lcu)

        #expect(result == .applied(pair(ignite, flash)))
        #expect(try sentPairs(lcu) == [pair(ignite, flash)])
    }

    @Test(arguments: flashInEitherSlot)
    func flashOnDAlwaysGoesInSpell1(_ recommended: SpellPair) async throws {
        let lcu = connection()
        let result = await apply(recommended, settings(.d), session(current: nil), on: lcu)

        #expect(result == .applied(pair(flash, ignite)))
        #expect(try sentPairs(lcu) == [pair(flash, ignite)])
    }

    @Test(arguments: flashInEitherSlot)
    func autoKeepsFlashOnDWhenTheCurrentSelectionHasItThere(_ recommended: SpellPair)
        async throws
    {
        let lcu = connection()
        _ = await apply(recommended, settings(.auto), session(current: (flash, smite)), on: lcu)

        #expect(try sentPairs(lcu) == [pair(flash, ignite)])
    }

    @Test(arguments: flashInEitherSlot)
    func autoKeepsFlashOnFWhenTheCurrentSelectionHasItThere(_ recommended: SpellPair)
        async throws
    {
        let lcu = connection()
        _ = await apply(recommended, settings(.auto), session(current: (smite, flash)), on: lcu)

        #expect(try sentPairs(lcu) == [pair(ignite, flash)])
    }

    @Test(arguments: flashInEitherSlot)
    func autoKeepsTheRecommendedOrderWhenTheCurrentSelectionHasNoFlash(
        _ recommended: SpellPair
    ) async throws {
        let lcu = connection()
        _ = await apply(recommended, settings(.auto), session(current: (smite, teleport)), on: lcu)

        #expect(try sentPairs(lcu) == [recommended])
    }

    @Test func autoKeepsTheRecommendedOrderWhenTheLocalPlayerIsNotInTheSession() async throws {
        let lcu = connection()
        _ = await apply(pair(ignite, flash), settings(.auto), session(current: nil), on: lcu)

        #expect(try sentPairs(lcu) == [pair(ignite, flash)])
    }

    @Test func autoReadsTheCurrentSlotFromARecordedSession() async throws {
        // The local player (cell 2) has Flash on D and Ignite on F.
        let body = try Data(
            contentsOf: Fixtures.url("lcu/cases/champ-select/ban-pick-in-progress.json"))
        let recorded = try LCUEndpoint.champSelectSession.decode(body)
        let lcu = connection()
        _ = await apply(pair(teleport, flash), settings(.auto), recorded, on: lcu)

        #expect(try sentPairs(lcu) == [pair(flash, teleport)])
    }

    @Test(arguments: [ImportSettings.FlashPosition.d, .f, .auto])
    func aPairWithoutFlashIsSentInItsOwnOrder(_ position: ImportSettings.FlashPosition)
        async throws
    {
        let lcu = connection()
        let result = await apply(
            pair(smite, ignite), settings(position), session(current: (flash, teleport)), on: lcu)

        #expect(result == .applied(pair(smite, ignite)))
        #expect(try sentPairs(lcu) == [pair(smite, ignite)])
    }

    @Test func nothingIsSentWhenTheResolvedPairIsAlreadySelected() async {
        let lcu = connection()
        let result = await apply(
            pair(flash, ignite), settings(.f), session(current: (ignite, flash)), on: lcu)

        #expect(result == .skipped(.alreadySelected))
        #expect(lcu.requests.isEmpty)
    }

    @Test func nothingIsSentWhenSpellImportIsOff() async {
        let lcu = connection()
        let result = await apply(
            pair(flash, ignite), settings(.auto, importSpells: false),
            session(current: (smite, teleport)), on: lcu)

        #expect(result == .skipped(.disabled))
        #expect(lcu.requests.isEmpty)
    }

    @Test func sendsOnePatchToMySelectionWithBothSpellIDs() async throws {
        let lcu = connection()
        _ = await apply(pair(flash, ignite), settings(.d), session(current: nil), on: lcu)

        #expect(lcu.requests.map(\.method) == [.patch])
        #expect(lcu.requests.map(\.path) == [mySelectionPath])
        let body = try #require(lcu.requests.first?.body)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Int]
        #expect(json == ["spell1Id": flash, "spell2Id": ignite])
    }

    @Test func aRejectedPatchIsReportedAsFailed() async {
        let lcu = connection(status: 500)
        let result = await apply(pair(flash, ignite), settings(.d), session(current: nil), on: lcu)

        #expect(result == .failed(.http(status: 500, body: Data())))
        #expect(lcu.writes.count == 1)
    }
}
