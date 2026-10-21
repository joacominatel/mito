import Foundation
import LCUKit
import MitoCore
import MitoStore
import Testing

@testable import Mito

/// What an import needs from the client, over a ranked solo gameflow session.
enum ImportWiringFixture {
    static func bodies() throws -> [String: Data] {
        var bodies = ImportFixture.gameData
        bodies[LCUEndpoint.currentSummoner.path] = try ImportFixture.data("full", in: "session")
        bodies[LCUEndpoint.perkStyles.path] = try ImportFixture.data("styles", in: "runes")
        bodies[LCUEndpoint.perkPages.path] = try ImportFixture.data(
            "pages-without-mito-page", in: "runes")
        bodies[LCUEndpoint.perkInventory.path] = try ImportFixture.data(
            "inventory-with-room", in: "runes")
        bodies[LCUEndpoint.gameflowSession.path] = try ImportFixture.data(
            "session-ranked-solo", in: "gameflow-lobby")
        bodies[LCUEndpoint.itemSets(summonerId: 1).path] = try ImportFixture.data(
            "empty", in: "item-sets")
        return bodies
    }

    /// Opens `ImportStats` in memory, never a file.
    static func snapshots(_ stats: any StatsProvider = ImportStats()) -> SnapshotModel {
        SnapshotModel(
            origin: .file(URL(filePath: "/in-memory/stats.sqlite")),
            open: { _ throws(SnapshotReadError) in stats })
    }

    /// `ban-pick-in-progress` with the local player hovering Ahri and no assigned role.
    static func blindHover() throws -> Data {
        var session = try #require(
            try JSONSerialization.jsonObject(with: ImportFixture.data("ban-pick-in-progress"))
                as? [String: Any])
        let team = try #require(session["myTeam"] as? [[String: Any]])
        session["myTeam"] = team.map { member in
            guard member["cellId"] as? Int == 2 else { return member }
            var me = member
            me["assignedPosition"] = ""
            return me
        }
        return try JSONSerialization.data(withJSONObject: session)
    }
}

@Suite(.timeLimit(.minutes(1)))
struct ImportWiringTests {
    @Test func blindPickImportsForTheSelectorsRole() async throws {
        var bodies = try ImportWiringFixture.bodies()
        // Served, not emitted: the fetch on connect would otherwise supersede the event.
        bodies[LCUEndpoint.champSelectSession.path] = try ImportWiringFixture.blindHover()
        let connection = BroadcastLCUConnection(bodies: bodies)
        let poster = RecordingPoster()
        let app = AppModel(
            connection: connection, snapshots: ImportWiringFixture.snapshots(), poster: poster,
            appIsActive: { false })
        let start = Task { await app.start() }

        await waitUntil { app.champSelect.canChooseRole && app.snapshots.status == .ready }
        app.champSelect.chooseRole(.middle)
        // Zed's most played role is JUNGLE: only the selector says MIDDLE.
        connection.emit(try ImportFixture.lockedSession(champion: 238, position: ""))
        await waitUntil { !poster.posts.isEmpty }
        connection.finish()
        await start.value

        #expect(poster.posts.map(\.title) == ["Importado para Zed MID"])
    }
}
