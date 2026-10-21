import LCUKit
import Testing

private let everyPhase: [GameflowPhase] = [
    .none, .lobby, .matchmaking, .readyCheck, .champSelect, .gameStart, .inProgress,
    .waitingForStats, .preEndOfGame, .endOfGame, .reconnect, .checkedIntoTournament,
    .unknown("PhaseFromAFuturePatch"),
]

private func connected(at phase: GameflowPhase? = nil) -> MitoStateMachine {
    var machine = MitoStateMachine()
    machine.apply(ConnectionState.connected)
    if let phase { machine.apply(phase) }
    return machine
}

struct MitoStateMachineTests {
    @Test func startsSearching() {
        #expect(MitoStateMachine().state == .searching)
    }

    @Test(arguments: [
        (ConnectionState.searching, MitoState.searching), (.connecting, .connecting),
    ])
    func reportsANonConnectedState(connection: ConnectionState, state: MitoState) {
        var machine = MitoStateMachine()
        machine.apply(connection)
        #expect(machine.state == state)
    }

    @Test func isIdleWhenConnectedBeforeAnyPhase() {
        #expect(connected().state == .idle)
    }

    @Test(arguments: [
        (GameflowPhase.none, MitoState.idle), (.lobby, .lobby),
        (.matchmaking, .matchmaking), (.readyCheck, .readyCheck),
        (.champSelect, .champSelect), (.gameStart, .inGame), (.inProgress, .inGame),
        (.reconnect, .inGame), (.waitingForStats, .idle), (.preEndOfGame, .idle),
        (.endOfGame, .idle), (.checkedIntoTournament, .lobby),
        (.unknown("PhaseFromAFuturePatch"), .idle),
    ])
    func mapsEachPhaseWhileConnected(phase: GameflowPhase, state: MitoState) {
        #expect(connected(at: phase).state == state)
    }

    @Test(arguments: everyPhase)
    func losingTheConnectionOverridesAnyPhase(_ phase: GameflowPhase) {
        var machine = connected(at: phase)
        machine.apply(ConnectionState.searching)
        #expect(machine.state == .searching)
        #expect(machine.phase == nil)
    }

    @Test func reconnectingDoesNotRestoreTheStalePhase() {
        var machine = connected(at: .champSelect)
        machine.apply(ConnectionState.connecting)
        machine.apply(ConnectionState.connected)
        #expect(machine.state == .idle)
    }

    @Test(arguments: [ConnectionState.searching, .connecting])
    func ignoresAPhaseWhileNotConnected(_ connection: ConnectionState) {
        var machine = MitoStateMachine()
        machine.apply(connection)
        machine.apply(GameflowPhase.champSelect)
        machine.apply(ConnectionState.connected)
        #expect(machine.state == .idle)
    }

    @Test func followsTheLatestPhase() {
        var machine = connected(at: .readyCheck)
        machine.apply(GameflowPhase.matchmaking)
        #expect(machine.state == .matchmaking)
    }

    @Test func aRepeatedConnectedKeepsThePhase() {
        var machine = connected(at: .lobby)
        machine.apply(ConnectionState.connected)
        #expect(machine.state == .lobby)
    }
}
