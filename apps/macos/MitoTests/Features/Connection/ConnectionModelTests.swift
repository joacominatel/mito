import Foundation
import LCUKit
import Observation
import Testing

@testable import Mito

struct ConnectionModelTests {
    @Test func startsSearchingBeforeAnyState() {
        let model = ConnectionModel(connection: ScriptedLCUConnection(script: []))

        #expect(model.state == .searching)
    }

    @Test(arguments: [
        ([ConnectionState.connecting], ConnectionState.connecting),
        ([.searching, .connecting], .connecting),
        ([.connecting, .connected], .connected),
        ([.connected, .searching], .searching),
        ([.connected, .searching, .connecting, .connected], .connected),
    ])
    func followsTheLatestStateFromTheConnection(script: [ConnectionState], last: ConnectionState)
        async
    {
        let model = ConnectionModel(connection: ScriptedLCUConnection(script: script))

        await model.run()

        #expect(model.state == last)
    }

    @Test func runReturnsAndKeepsTheStateWhenTheStreamFinishes() async {
        let model = ConnectionModel(
            connection: ScriptedLCUConnection(script: []), state: .connected)

        await model.run()

        #expect(model.state == .connected)
    }

    @Test(arguments: [
        (ConnectionState.searching, "circle.dashed", "Mito — Buscando el cliente…"),
        (.connecting, "circle.dashed", "Mito — Conectando…"),
        (.connected, "circle.fill", "Mito — Conectado"),
    ])
    func presentsSymbolAndStatusPerState(state: ConnectionState, symbol: String, status: String) {
        let model = ConnectionModel(connection: ScriptedLCUConnection(script: []), state: state)

        #expect(model.menuBarSymbol == symbol)
        #expect(String(localized: model.status) == status)
        #expect(model.isConnected == (state == .connected))
        #expect(model.isConnecting == (state == .connecting))
    }

    @Test func statusResolvesFromTheConnectionTable() {
        let model = ConnectionModel(connection: ScriptedLCUConnection(script: []))

        #expect(model.status.table == "Connection")
    }
}

@Suite(.timeLimit(.minutes(1)))
struct ConnectionModelRiotIDTests {
    let connection = ControlledLCUConnection()

    @Test func showsTheRiotIDOnceConnected() async {
        let model = ConnectionModel(connection: connection)
        var requests = connection.requests.makeAsyncIterator()
        let run = Task { await model.run() }

        connection.enter(.connected)
        await requests.next()?.respond(.success(Self.joaco))
        await until { model.riotID != nil }

        #expect(String(localized: model.status) == "Mito — Conectado como Joaco#LAS")
        await stop(run)
    }

    @Test func fallsBackToConnectedWhenTheFetchFails() async {
        let model = ConnectionModel(connection: connection, state: .connected, riotID: "Joaco#LAS")
        var requests = connection.requests.makeAsyncIterator()

        let fetch = Task { await model.refreshRiotID() }
        await requests.next()?.respond(.failure(.http(status: 404, body: Data())))
        await fetch.value

        #expect(model.riotID == nil)
        #expect(String(localized: model.status) == "Mito — Conectado")
    }

    @Test(arguments: [
        CurrentSummoner(),
        CurrentSummoner(gameName: "Joaco"),
        CurrentSummoner(gameName: "", tagLine: "LAS"),
        CurrentSummoner(gameName: "Joaco", tagLine: ""),
    ])
    func fallsBackToConnectedWithoutARiotID(summoner: CurrentSummoner) async {
        let model = ConnectionModel(connection: connection, state: .connected, riotID: "Joaco#LAS")
        var requests = connection.requests.makeAsyncIterator()

        let fetch = Task { await model.refreshRiotID() }
        await requests.next()?.respond(.success(summoner))
        await fetch.value

        #expect(model.riotID == nil)
        #expect(String(localized: model.status) == "Mito — Conectado")
    }

    @Test(arguments: [ConnectionState.searching, .connecting])
    func clearsTheRiotIDWhenTheConnectionDrops(next: ConnectionState) async {
        let model = ConnectionModel(connection: connection)
        var requests = connection.requests.makeAsyncIterator()
        let run = Task { await model.run() }
        connection.enter(.connected)
        await requests.next()?.respond(.success(Self.joaco))
        await until { model.riotID != nil }

        connection.enter(next)
        await until { model.state == next }

        #expect(model.riotID == nil)
        await stop(run)
    }

    @Test func refetchesWhenTheAccountChanges() async {
        let model = ConnectionModel(connection: connection)
        var requests = connection.requests.makeAsyncIterator()
        let run = Task { await model.run() }
        connection.enter(.connected)
        await requests.next()?.respond(.success(Self.joaco))
        await until { model.riotID == "Joaco#LAS" }

        connection.changeAccount()
        await requests.next()?.respond(.success(CurrentSummoner(gameName: "Otra", tagLine: "BR1")))
        await until { model.riotID == "Otra#BR1" }

        #expect(String(localized: model.status) == "Mito — Conectado como Otra#BR1")
        await stop(run)
    }

    @Test func ignoresAFetchThatFinishesAfterTheConnectionDropped() async {
        let model = ConnectionModel(connection: connection)
        var requests = connection.requests.makeAsyncIterator()
        let run = Task { await model.run() }
        connection.enter(.connected)
        await requests.next()?.respond(.success(Self.joaco))
        await until { model.riotID != nil }

        let stale = Task { await model.refreshRiotID() }
        let staleRequest = await requests.next()
        connection.enter(.searching)
        connection.enter(.connected)
        let freshRequest = await requests.next()
        staleRequest?.respond(.success(CurrentSummoner(gameName: "Vieja", tagLine: "LAS")))
        await stale.value

        #expect(model.riotID == nil)
        freshRequest?.respond(.success(Self.joaco))
        await until { model.riotID == "Joaco#LAS" }
        await stop(run)
    }

    private static let joaco = CurrentSummoner(gameName: "Joaco", tagLine: "LAS")

    private func stop(_ run: Task<Void, Never>) async {
        connection.finish()
        await run.value
    }
}

/// Suspends until `condition` holds, re-checking on every change to what it reads.
private func until(_ condition: () -> Bool) async {
    while !condition() {
        await withCheckedContinuation { continuation in
            withObservationTracking {
                _ = condition()
            } onChange: {
                continuation.resume()
            }
        }
    }
}
