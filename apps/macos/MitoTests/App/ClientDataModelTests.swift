import Foundation
import LCUKit
import MitoAssets
import MitoCore
import Testing

@testable import Mito

@Suite(.timeLimit(.minutes(1)))
struct ClientDataModelTests {
    @Test func loadsTheStaticDataAndTheVersionOnConnect() async {
        let model = ClientDataModel(
            connection: ServingLCUConnection(
                script: [.connecting, .connected], bodies: ClientDataFixture.bodies()))
        #expect(model.patch == Patch(rawValue: ""))

        await model.run()

        #expect(model.gameData?.champion(ChampionID(rawValue: 103))?.name == "Ahri")
        #expect(model.gameVersion?.rawValue == "16.21.723.1234")
        #expect(model.patch == Patch(rawValue: "16.21"))
    }

    @Test func readsOncePerConnection() async {
        let connection = ServingLCUConnection(
            script: [.connected, .searching, .connecting, .connected],
            bodies: ClientDataFixture.bodies())
        let model = ClientDataModel(connection: connection)

        await model.run()

        #expect(connection.requests(to: LCUEndpoint.gameVersion.path) == 2)
        for path in ClientDataFixture.staticDataPaths {
            #expect(connection.requests(to: path) == 2, "\(path)")
        }
    }

    @Test func anUnreadableVersionLeavesThePatchEmpty() async {
        let model = ClientDataModel(
            connection: ServingLCUConnection(
                script: [.connected], bodies: ClientDataFixture.bodies(version: false)))

        await model.run()

        #expect(model.gameData != nil)
        #expect(model.gameVersion == nil)
        #expect(model.patch == Patch(rawValue: ""))
    }
}

@Suite(.timeLimit(.minutes(1)))
struct ClientDataReloadTests {
    @Test func aFailedReloadKeepsTheLastDataAndDropsTheVersion() async {
        let connection = GameflowTestConnection()
        for (path, body) in ClientDataFixture.bodies() {
            connection.answer(path, json: String(decoding: body, as: UTF8.self))
        }
        let model = ClientDataModel(connection: connection)
        let run = Task { await model.run() }
        connection.enter(.connected)
        await waitUntil { model.gameData != nil && model.gameVersion != nil }

        connection.answer(
            LCUEndpoint.gameDataChampions.path, error: .http(status: 500, body: Data()))
        connection.answer(LCUEndpoint.gameVersion.path, error: .http(status: 500, body: Data()))
        connection.enter(.searching)
        connection.enter(.connected)
        connection.finish()
        await run.value

        #expect(connection.count(.get, LCUEndpoint.gameDataChampions.path) == 2)
        #expect(model.gameData?.champion(ChampionID(rawValue: 103))?.name == "Ahri")
        #expect(model.gameVersion == nil)
        #expect(model.patch == Patch(rawValue: ""))
    }
}
