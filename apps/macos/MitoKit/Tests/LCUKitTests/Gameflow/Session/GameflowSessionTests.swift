import Foundation
import LCUKit
import MitoCore
import MitoTestSupport
import Testing

private func sessionBody(_ name: String) throws -> Data {
    try Data(contentsOf: Fixtures.url("lcu/cases/gameflow-lobby/session-\(name).json"))
}

private func decodeSession(_ name: String) throws -> GameflowSession {
    try LCUEndpoint.gameflowSession.decode(sessionBody(name))
}

struct GameflowSessionTests {
    @Test func decodesARankedSoloSessionAndIgnoresItsMalformedRosters() throws {
        let session = try decodeSession("ranked-solo")
        #expect(session == GameflowSession(queueID: QueueID(rawValue: 420), mapID: 11))
        #expect(session.queueType == .rankedSolo)
    }

    @Test func decodesAnARAMSessionOnHowlingAbyss() throws {
        let session = try decodeSession("aram")
        #expect(session == GameflowSession(queueID: QueueID(rawValue: 450), mapID: 12))
        #expect(session.queueType == .aram)
    }

    @Test func aMissingQueueDecodesAsNil() throws {
        let session = try decodeSession("missing-queue")
        #expect(session == GameflowSession())
        #expect(session.queueType == nil)
    }

    @Test func anUnknownQueueIsOther() throws {
        let session = try decodeSession("unknown-queue")
        #expect(session.queueType == .other(QueueID(rawValue: 9999)))
        #expect(session.mapID == 30)
    }

    @Test(arguments: ["{}", #"{"gameData":null}"#, #"{"gameData":{"queue":null}}"#])
    func anAbsentGameDataOrQueueDecodesAsNil(_ json: String) throws {
        #expect(try LCUEndpoint.gameflowSession.decode(Data(json.utf8)) == GameflowSession())
    }

    @Test func rosterIdentityIsNotKept() throws {
        let session = try decodeSession("ranked-solo")
        let forms = [
            String(describing: session), String(reflecting: session),
            String(describing: Mirror(reflecting: session).children.map(\.value)),
        ]
        for form in forms {
            for identity in ["00000000-0000-0000-0000-00000000000", "Fake", "TEST"] {
                #expect(!form.contains(identity))
            }
        }
        #expect(Mirror(reflecting: session).children.compactMap(\.label) == ["queueID", "mapID"])
    }

    @Test(arguments: ["", "null", #""ChampSelect""#, "[]", #"{"gameData":{"queue":{"id":"420"}}}"#])
    func aMalformedBodyIsADecodingError(_ json: String) {
        #expect {
            try LCUEndpoint.gameflowSession.decode(Data(json.utf8))
        } throws: { error in
            if case .decoding = error as? LCUError { true } else { false }
        }
    }
}

struct GameflowSessionEndpointTests {
    @Test func isAGetOnTheGameflowSessionPath() {
        let endpoint = LCUEndpoint.gameflowSession
        #expect(endpoint.method == .get)
        #expect(endpoint.path == "/lol-gameflow/v1/session")
        #expect(endpoint.body == nil)
    }

    @Test func sendsThroughAConnection() async throws {
        let connection = FakeLCUConnection(responses: [
            .init(method: .get, path: "/lol-gameflow/v1/session", body: try sessionBody("aram"))
        ])
        #expect(try await connection.send(.gameflowSession).queueType == .aram)
        #expect(connection.requests.map(\.path) == ["/lol-gameflow/v1/session"])
    }
}
