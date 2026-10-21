import Foundation
import LCUKit
import MitoCore
import Testing

@testable import Mito

private let phasePath = LCUEndpoint.gameflowPhase.path
private let sessionPath = LCUEndpoint.gameflowSession.path
private let readyCheckPath = LCUEndpoint.readyCheck.path
private let acceptPath = LCUEndpoint.acceptReadyCheck.path
private let showing = #"{"state":"InProgress","playerResponse":"None"}"#
nonisolated private let answered = #"{"state":"InProgress","playerResponse":"Accepted"}"#
private let found = RecordingPoster.Post(notification: .matchFound, title: "Partida encontrada")
private let accepted = RecordingPoster.Post(
    notification: .matchFound, title: "Partida encontrada, aceptada")

private func session(queue: Int) -> String {
    #"{"gameData":{"queue":{"id":\#(queue),"mapId":11}}}"#
}

/// Settings the test changes while the model runs.
private final class SettingsBox {
    var value: GameSettings

    init(_ value: GameSettings) { self.value = value }
}

/// One model over a hand-driven connection, an immediate clock, and a recording poster.
private struct Harness {
    let connection = GameflowTestConnection()
    let clock = ImmediateClock()
    let poster = RecordingPoster()
    let settings: SettingsBox
    let model: GameflowModel

    init(settings: GameSettings = GameSettings()) {
        let box = SettingsBox(settings)
        self.settings = box
        model = GameflowModel(
            connection: connection, settings: { box.value }, poster: poster, clock: clock)
    }

    func start() -> Task<Void, Never> {
        let model = model
        return Task { await model.run() }
    }

    /// Connects and waits out the ready-check read every connection makes.
    func connect() async {
        let reads = connection.count(.get, readyCheckPath)
        connection.enter(.connected)
        await connection.requested(.get, readyCheckPath, times: reads + 1)
    }

    func stop(_ run: Task<Void, Never>) async {
        connection.finish()
        await run.value
    }
}

@Suite(.timeLimit(.minutes(1)))
struct GameflowModelPhaseTests {
    @Test(
        arguments: [
            ("Lobby", "Fase: Lobby", nil, "person.2"),
            ("Matchmaking", "Fase: Buscando partida", "magnifyingglass", "magnifyingglass"),
            ("ReadyCheck", "Fase: Partida encontrada", nil, "bell.badge"),
            ("ChampSelect", "Fase: Champ select", "person.3.fill", "person.3.fill"),
            ("InProgress", "Fase: En partida", "gamecontroller.fill", "gamecontroller.fill"),
            ("Reconnect", "Fase: En partida", "gamecontroller.fill", "gamecontroller.fill"),
            ("EndOfGame", "Sin partida en curso", nil, "moon.zzz"),
            ("SomethingNew", "Sin partida en curso", nil, "moon.zzz"),
        ] as [(String, String, String?, String)])
    func showsEachPhaseInTheMenu(
        phase: String, title: String, menuBarSymbol: String?, phaseSymbol: String
    ) async {
        let harness = Harness()
        let run = harness.start()
        await harness.connect()

        harness.connection.emitPhase(phase)
        await waitUntil { harness.model.state == MitoStateMachine.state(after: phase) }

        #expect(String(localized: harness.model.phaseTitle) == title)
        #expect(harness.model.menuBarSymbol == menuBarSymbol)
        #expect(harness.model.phaseSymbol == phaseSymbol)
        await harness.stop(run)
    }

    @Test(arguments: [ConnectionState.searching, .connecting])
    func leavesTheConnectionSymbolWhileDisconnected(state: ConnectionState) async {
        let harness = Harness()
        harness.connection.answer(phasePath, json: #""ChampSelect""#)
        let run = harness.start()
        await harness.connect()
        await waitUntil { harness.model.state == .champSelect }

        harness.connection.enter(state)
        await waitUntil { harness.model.state != .champSelect }

        #expect(harness.model.menuBarSymbol == nil)
        #expect(String(localized: harness.model.phaseTitle) == "Sin partida en curso")
        await harness.stop(run)
    }

    @Test func readsThePhaseOnConnectAndOnEveryReconnect() async {
        let harness = Harness()
        harness.connection.answer(phasePath, json: #""ChampSelect""#)
        let run = harness.start()

        await harness.connect()
        await waitUntil { harness.model.state == .champSelect }
        harness.connection.enter(.searching)
        await waitUntil { harness.model.state == .searching }
        harness.connection.answer(phasePath, json: #""Matchmaking""#)
        await harness.connect()
        await waitUntil { harness.model.state == .matchmaking }

        #expect(harness.model.menuBarSymbol == "magnifyingglass")
        #expect(harness.connection.count(.get, phasePath) == 2)
        await harness.stop(run)
    }

    @Test func aPhaseEventBeatsAnOlderRead() async {
        let harness = Harness()
        harness.connection.answer(phasePath, json: #""Lobby""#)
        harness.connection.hold(phasePath)
        let run = harness.start()
        harness.connection.enter(.connected)
        await harness.connection.requested(.get, phasePath)

        harness.connection.emitPhase("ChampSelect")
        await waitUntil { harness.model.state == .champSelect }
        harness.connection.release(phasePath)
        await harness.stop(run)

        #expect(harness.model.state == .champSelect)
    }

    @Test func staysIdleWhenThePhaseCannotBeRead() async {
        let harness = Harness()
        let run = harness.start()

        await harness.connect()
        await harness.connection.requested(.get, phasePath)
        await harness.stop(run)

        #expect(harness.model.state == .idle)
        #expect(harness.model.menuBarSymbol == nil)
    }
}

@Suite(.timeLimit(.minutes(1)))
struct GameflowModelAutoAcceptTests {
    @Test func acceptsAReadyCheckAfterTheConfiguredDelay() async {
        let harness = Harness(
            settings: GameSettings(autoAccept: .always, autoAcceptDelaySeconds: 5))
        let run = harness.start()
        await harness.connect()

        harness.connection.answer(readyCheckPath, json: showing)
        harness.connection.answer(acceptPath, json: "")
        harness.connection.emitReadyCheck(showing)
        await harness.connection.requested(.post, acceptPath)
        await harness.stop(run)

        #expect(harness.clock.sleeps == [.seconds(5)])
        #expect(harness.connection.count(.post, acceptPath) == 1)
    }

    @Test func neverAnswersWhenOff() async {
        let harness = Harness(settings: GameSettings(autoAccept: .off))
        let run = harness.start()
        await harness.connect()

        harness.connection.answer(readyCheckPath, json: showing)
        harness.connection.answer(acceptPath, json: "")
        harness.connection.emitReadyCheck(showing)
        await harness.connection.requested(.get, sessionPath)
        await harness.stop(run)

        #expect(harness.connection.count(.post, acceptPath) == 0)
        #expect(harness.clock.sleeps.isEmpty)
    }

    @Test func aSettingsChangeAppliesAtTheNextReadyCheck() async {
        let harness = Harness(settings: GameSettings(autoAccept: .off))
        let run = harness.start()
        await harness.connect()
        harness.connection.answer(readyCheckPath, json: showing)
        harness.connection.answer(acceptPath, json: "")
        harness.connection.emitReadyCheck(showing)
        await harness.connection.requested(.get, sessionPath)

        harness.settings.value.autoAccept = .always
        harness.connection.emitReadyCheckEnded()
        harness.connection.emitReadyCheck(showing)
        await harness.connection.requested(.post, acceptPath)
        await harness.stop(run)

        #expect(harness.connection.count(.post, acceptPath) == 1)
    }

    @Test(arguments: [(420, true), (440, false)])
    func decidesSelectedQueuesByTheSessionQueue(queue: Int, accepts: Bool) async {
        let harness = Harness(
            settings: GameSettings(
                autoAccept: .selectedQueues, autoAcceptQueues: [QueueID(rawValue: 420)]))
        harness.connection.answer(sessionPath, json: session(queue: queue))
        let run = harness.start()
        await harness.connect()

        harness.connection.answer(readyCheckPath, json: showing)
        harness.connection.answer(acceptPath, json: "")
        harness.connection.emitReadyCheck(showing)
        if accepts {
            await harness.connection.requested(.post, acceptPath)
        } else {
            await harness.connection.requested(.get, sessionPath)
        }
        await harness.stop(run)

        #expect(harness.connection.count(.post, acceptPath) == (accepts ? 1 : 0))
    }

    @Test func answersAReadyCheckAlreadyShowingOnConnect() async {
        let harness = Harness()
        harness.connection.answer(readyCheckPath, json: showing)
        harness.connection.answer(acceptPath, json: "")
        let run = harness.start()

        harness.connection.enter(.connected)
        await harness.connection.requested(.post, acceptPath)
        await harness.stop(run)

        #expect(harness.connection.count(.post, acceptPath) == 1)
        #expect(harness.poster.posts.count == 1)
    }

    @Test func answersANewReadyCheckShowingAfterAReconnect() async {
        let harness = Harness()
        harness.connection.answer(readyCheckPath, json: showing)
        harness.connection.answer(acceptPath, json: "")
        let run = harness.start()
        harness.connection.enter(.connected)
        await harness.connection.requested(.post, acceptPath)

        harness.connection.enter(.searching)
        harness.connection.enter(.connected)
        await harness.connection.requested(.post, acceptPath, times: 2)
        await harness.stop(run)

        #expect(harness.connection.count(.post, acceptPath) == 2)
    }
}

@Suite(.timeLimit(.minutes(1)))
struct GameflowModelNotificationTests {
    @Test func postsMatchAcceptedOnceWhenTheAcceptGoesThrough() async {
        let harness = Harness()
        let run = harness.start()
        await harness.connect()

        harness.connection.answer(readyCheckPath, json: showing)
        harness.connection.answer(acceptPath, json: "")
        harness.connection.emitReadyCheck(showing)
        await waitUntil { !harness.poster.posts.isEmpty }
        harness.connection.emitReadyCheck(answered)
        harness.connection.emitReadyCheck(answered)
        await harness.stop(run)

        #expect(harness.poster.posts == [accepted])
    }

    @Test func postsMatchFoundWhenOff() async {
        let harness = Harness(settings: GameSettings(autoAccept: .off))
        let run = harness.start()
        await harness.connect()

        harness.connection.emitReadyCheck(showing)
        await waitUntil { !harness.poster.posts.isEmpty }
        await harness.stop(run)

        #expect(harness.poster.posts == [found])
        #expect(harness.connection.count(.post, acceptPath) == 0)
    }

    /// 440 is not selected; with no session the queue is unknown.
    @Test(arguments: [440, nil] as [Int?])
    func postsMatchFoundWhenTheQueueIsNotAccepted(queue: Int?) async {
        let harness = Harness(
            settings: GameSettings(
                autoAccept: .selectedQueues, autoAcceptQueues: [QueueID(rawValue: 420)]))
        if let queue { harness.connection.answer(sessionPath, json: session(queue: queue)) }
        let run = harness.start()
        await harness.connect()

        harness.connection.emitReadyCheck(showing)
        await waitUntil { !harness.poster.posts.isEmpty }
        await harness.stop(run)

        #expect(harness.poster.posts == [found])
        #expect(harness.connection.count(.post, acceptPath) == 0)
    }

    @Test func postsMatchFoundWhenAutoAcceptIsTurnedOffDuringTheDelay() async {
        let harness = Harness()
        let run = harness.start()
        await harness.connect()
        harness.connection.hold(readyCheckPath)

        harness.connection.emitReadyCheck(showing)
        await harness.connection.requested(.get, readyCheckPath, times: 2)
        harness.settings.value.autoAccept = .off
        harness.connection.answer(readyCheckPath, json: showing)
        harness.connection.release(readyCheckPath)
        await waitUntil { !harness.poster.posts.isEmpty }
        await harness.stop(run)

        #expect(harness.poster.posts == [found])
        #expect(harness.connection.count(.post, acceptPath) == 0)
    }

    @Test func postsMatchFoundOncePerReadyCheck() async {
        let harness = Harness(settings: GameSettings(autoAccept: .off))
        let run = harness.start()
        await harness.connect()

        harness.connection.emitReadyCheck(showing)
        harness.connection.emitReadyCheck(showing)
        harness.connection.emitReadyCheck(answered)
        harness.connection.emitReadyCheck(showing)
        await waitUntil { !harness.poster.posts.isEmpty }
        harness.connection.emitReadyCheckEnded()
        harness.connection.emitReadyCheck(showing)
        harness.connection.emitReadyCheck(showing)
        await waitUntil { harness.poster.posts.count == 2 }
        await harness.stop(run)

        #expect(harness.poster.posts == [found, found])
    }

    /// The connect read comes back after the live stream showed and ended the same ready check.
    /// `off`, and `selectedQueues` with an unselected queue: both notify without answering.
    @Test(
        arguments: [
            GameSettings(autoAccept: .off),
            GameSettings(autoAccept: .selectedQueues, autoAcceptQueues: [QueueID(rawValue: 420)]),
        ])
    func postsMatchFoundOnceWhenTheConnectReadLandsAfterTheLiveEnd(settings: GameSettings) async {
        let harness = Harness(settings: settings)
        harness.connection.answer(sessionPath, json: session(queue: 440))
        harness.connection.answer(readyCheckPath, json: showing)
        harness.connection.hold(readyCheckPath)
        let run = harness.start()
        harness.connection.enter(.connected)
        await harness.connection.requested(.get, readyCheckPath)

        harness.connection.emitReadyCheck(showing)
        harness.connection.emitReadyCheckEnded()
        await waitUntil { harness.model.readyCheckGeneration == 2 }
        harness.connection.release(readyCheckPath)
        await harness.stop(run)

        #expect(harness.poster.posts == [found])
    }

    @Test func staysQuietWhenOffWithNotifyMatchFoundOff() async {
        let harness = Harness(settings: GameSettings(autoAccept: .off, notifyMatchFound: false))
        let run = harness.start()
        await harness.connect()

        harness.connection.emitReadyCheck(showing)
        await harness.connection.requested(.get, sessionPath)
        await harness.stop(run)

        #expect(harness.poster.posts.isEmpty)
    }

    /// Answered from the client, or already over: nothing left to tell the user.
    @Test(
        arguments: [
            answered,
            #"{"state":"InProgress","playerResponse":"Declined"}"#,
            #"{"state":"EveryoneReady","playerResponse":"Accepted"}"#,
            #"{"state":"StrangerNotReady","playerResponse":"None"}"#,
            nil,
        ] as [String?])
    func staysQuietWhenOffForAReadyCheckNotWaitingOnTheUser(readyCheck: String?) async {
        let harness = Harness(settings: GameSettings(autoAccept: .off))
        let run = harness.start()
        await harness.connect()

        if let readyCheck {
            harness.connection.emitReadyCheck(readyCheck)
        } else {
            harness.connection.emitReadyCheckEnded()
        }
        await harness.stop(run)

        #expect(harness.poster.posts.isEmpty)
        #expect(harness.connection.count(.get, sessionPath) == 0)
    }

    /// The accepter withdraws the waiting accept and reports why; none of those reasons notify.
    @Test(
        arguments: [
            answered,
            #"{"state":"InProgress","playerResponse":"Declined"}"#,
            #"{"state":"EveryoneReady","playerResponse":"Accepted"}"#,
            nil,
        ] as [String?])
    func staysQuietWhenTheReadyCheckChangesDuringTheDelay(readyCheck: String?) async {
        let harness = Harness()
        let run = harness.start()
        await harness.connect()
        harness.connection.hold(readyCheckPath)

        harness.connection.emitReadyCheck(showing)
        await harness.connection.requested(.get, readyCheckPath, times: 2)
        if let readyCheck {
            harness.connection.emitReadyCheck(readyCheck)
        } else {
            harness.connection.emitReadyCheckEnded()
        }
        harness.connection.release(readyCheckPath)
        await harness.stop(run)

        #expect(harness.poster.posts.isEmpty)
        #expect(harness.connection.count(.post, acceptPath) == 0)
    }

    @Test func staysQuietWithNotifyMatchFoundOff() async {
        let harness = Harness(settings: GameSettings(notifyMatchFound: false))
        let run = harness.start()
        await harness.connect()

        harness.connection.answer(readyCheckPath, json: showing)
        harness.connection.answer(acceptPath, json: "")
        harness.connection.emitReadyCheck(showing)
        await harness.connection.requested(.post, acceptPath)
        await harness.stop(run)

        #expect(harness.poster.posts.isEmpty)
    }

    @Test func staysQuietWhenTheAcceptFails() async {
        let harness = Harness()
        let run = harness.start()
        await harness.connect()

        harness.connection.answer(readyCheckPath, json: showing)
        harness.connection.answer(acceptPath, error: .http(status: 500, body: Data()))
        harness.connection.emitReadyCheck(showing)
        await harness.connection.requested(.post, acceptPath)
        await harness.stop(run)

        #expect(harness.poster.posts.isEmpty)
    }

    @Test func staysQuietWhenTheReadyCheckEndsBeforeTheAccept() async {
        let harness = Harness()
        let run = harness.start()
        await harness.connect()

        harness.connection.emitReadyCheck(showing)
        await harness.connection.requested(.get, readyCheckPath, times: 2)
        await harness.stop(run)

        #expect(harness.connection.count(.post, acceptPath) == 0)
        #expect(harness.poster.posts.isEmpty)
    }
}

struct GameSettingsQueueSelectionTests {
    @Test func togglesAQueueInTheSelection() {
        var settings = GameSettings()
        let ranked = QueueID(rawValue: 420)

        settings[autoAccepts: ranked] = true
        #expect(settings.autoAcceptQueues == [ranked])
        #expect(settings[autoAccepts: ranked])

        settings[autoAccepts: ranked] = false
        #expect(settings.autoAcceptQueues.isEmpty)
        #expect(!settings[autoAccepts: ranked])
    }
}

extension MitoStateMachine {
    fileprivate static func state(after phase: String) -> MitoState {
        var machine = MitoStateMachine()
        machine.apply(.connected)
        machine.apply(GameflowPhase(phase))
        return machine.state
    }
}

@Suite(.timeLimit(.minutes(1)))
struct GameflowModelMatchFlowTests {
    @Test(
        arguments: [
            ("Lobby", true), ("Matchmaking", true), ("ReadyCheck", true), ("ChampSelect", true),
            ("InProgress", true), ("EndOfGame", false), ("None", false),
        ])
    func isInMatchFlowFromTheLobbyUntilTheGameEnds(phase: String, inFlow: Bool) async {
        let harness = Harness()
        let run = harness.start()
        await harness.connect()
        #expect(!harness.model.isInMatchFlow)

        harness.connection.emitPhase(phase)
        await waitUntil { harness.model.state == MitoStateMachine.state(after: phase) }

        #expect(harness.model.isInMatchFlow == inFlow)
        await harness.stop(run)
    }

    @Test func aDisconnectLeavesTheMatchFlow() async {
        let harness = Harness()
        harness.connection.answer(phasePath, json: #""InProgress""#)
        let run = harness.start()
        await harness.connect()
        await waitUntil { harness.model.state == .inGame }

        harness.connection.enter(.searching)
        await waitUntil { harness.model.state == .searching }

        #expect(!harness.model.isInMatchFlow)
        await harness.stop(run)
    }
}
