import Foundation
import LCUKit
import MitoCore
import Testing

@testable import Mito

/// §20.3: Flex (440) and Normal Draft (400) read the 420 snapshot like Ranked Solo/Duo, with no
/// notice of their own: the column, the analysis, and the import come out the same.
@Suite(.timeLimit(.minutes(1)))
struct QueueWiringTests {
    /// What one champ select shows and imports: Ahri MID locked against Darius TOP, so Zed is
    /// still there to recommend.
    private struct Outcome {
        let queue: QueueType?
        let recommendations: RecommendationList?
        let missingSnapshot: [AnalysisModel.Tab]
        let matchup: MatchupPresentation?
        let build: BuildContent?
        let posts: [RecordingPoster.Post]
        /// The page `POST`, decoded: the encoder does not keep key order.
        let runePage: NSDictionary?
    }

    private func champSelect(inQueue queueID: Int) async throws -> Outcome {
        var bodies = try ImportWiringFixture.bodies()
        bodies[LCUEndpoint.gameflowSession.path] = try Self.gameflowSession(queueID: queueID)
        let session = try ImportFixture.lockedSession(enemies: [(122, "top")])
        bodies[LCUEndpoint.champSelectSession.path] = session
        let connection = BroadcastLCUConnection(bodies: bodies)
        let poster = RecordingPoster()
        var settings = MitoSettings()
        settings.champSelect.candidates = .all
        let app = AppModel(
            connection: connection, settings: SettingsModel(value: settings),
            snapshots: ImportWiringFixture.snapshots(), poster: poster, appIsActive: { false })
        let start = Task { await app.start() }

        connection.emit(session)
        await waitUntil {
            app.champSelect.draft != nil && app.snapshots.status == .ready
                && !poster.posts.isEmpty
        }
        connection.finish()
        await start.value

        let missing = AnalysisModel.Tab.allCases.filter { tab in
            app.analysis.tab = tab
            return app.analysis.isMissingSnapshot
        }
        let subject = app.analysis.subject
        return Outcome(
            queue: app.champSelect.draft?.queue,
            recommendations: app.champSelect.recommendations, missingSnapshot: missing,
            matchup: subject.map { MatchupPresentation(subject: $0) },
            build: subject.map { BuildContent.derive($0, settings: ImportSettings()) },
            posts: poster.posts,
            runePage: try connection.writes(.post, LCUEndpoint.perkPages.path).first?.body.map {
                try JSONSerialization.jsonObject(with: $0) as? NSDictionary
            } ?? nil)
    }

    private static func gameflowSession(queueID: Int) throws -> Data {
        var session = try #require(
            try JSONSerialization.jsonObject(
                with: ImportFixture.data("session-ranked-solo", in: "gameflow-lobby"))
                as? [String: Any])
        var gameData = try #require(session["gameData"] as? [String: Any])
        var queue = try #require(gameData["queue"] as? [String: Any])
        queue["id"] = queueID
        gameData["queue"] = queue
        session["gameData"] = gameData
        return try JSONSerialization.data(withJSONObject: session)
    }

    @Test(arguments: [(440, QueueType.rankedFlex), (400, .normalDraft)])
    func readsTheRankedSoloSnapshotLikeRankedSolo(queueID: Int, queue: QueueType) async throws {
        let solo = try await champSelect(inQueue: 420)
        let other = try await champSelect(inQueue: queueID)

        #expect(other.queue == queue)
        guard case .picks(let picks)? = other.recommendations else {
            Issue.record(
                "Expected pick recommendations, got \(String(describing: other.recommendations))")
            return
        }
        #expect(!picks.isEmpty)
        #expect(other.recommendations == solo.recommendations)
        #expect(other.missingSnapshot.isEmpty)
        guard case .ready? = other.matchup, case .loadout? = other.build?.state else {
            Issue.record(
                "Expected the matchup and the build, got \(String(describing: other.build))")
            return
        }
        #expect(other.matchup == solo.matchup)
        #expect(other.build == solo.build)
        #expect(
            other.posts.map(\.notification) == [
                .loadoutImported(
                    champion: ChampionID(rawValue: 103), opponent: nil)
            ])
        #expect(other.posts == solo.posts)
        #expect(other.runePage != nil)
        #expect(other.runePage == solo.runePage)
    }
}
