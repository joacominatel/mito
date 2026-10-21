import Foundation
import LCUKit
import MitoCore
import MitoTestSupport
import Testing

private typealias Session = ChampSelectSession
private typealias Member = ChampSelectSession.Member
private typealias Action = ChampSelectSession.Action

private let patch = Patch(rawValue: "16.21")
private let pickable: Set<ChampionID> = [champion(103), champion(64)]

private func champion(_ id: Int) -> ChampionID { ChampionID(rawValue: id) }

private func decodeCase(_ name: String) throws -> Session {
    try LCUEndpoint.champSelectSession.decode(
        Data(contentsOf: Fixtures.url("lcu/cases/champ-select/\(name).json")))
}

private func context(_ session: Session) throws -> DraftContext {
    try #require(session.draftContext(queue: .rankedSolo, patch: patch, pickable: pickable))
}

private func session(
    localPlayerCellId: Int? = 2,
    myTeam: [Member] = [Member(cellId: 2)],
    theirTeam: [Member] = [],
    actions: [[Action]] = [],
    bans: Session.Bans = Session.Bans(),
    phase: Session.Timer.Phase? = .banPick
) -> Session {
    Session(
        localPlayerCellId: localPlayerCellId, myTeam: myTeam, theirTeam: theirTeam,
        actions: actions, bans: bans, timer: Session.Timer(phase: phase))
}

private func slot(
    _ cellId: Int, champion: ChampionID? = nil, hover: ChampionID? = nil, role: Role? = nil
) -> DraftSlot {
    DraftSlot(
        cellId: cellId, champion: champion, hover: hover, role: role,
        roleConfidence: role == nil ? 0 : 1)
}

private func action(
    _ type: Action.Kind, actor: Int, champion: ChampionID? = nil, inProgress: Bool,
    completed: Bool
) -> Action {
    Action(
        actorCellId: actor, championId: champion, type: type, isInProgress: inProgress,
        completed: completed)
}

struct DraftContextMappingTests {
    @Test func mapsAPlanningSession() throws {
        let draft = try decodeCase("planning")
            .draftContext(queue: .normalDraft, patch: patch, pickable: pickable)
        #expect(
            draft
                == DraftContext(
                    queue: .normalDraft, patch: patch, myRole: .middle, myCellId: 2,
                    allies: [
                        slot(0, role: .top), slot(1, hover: champion(64), role: .jungle),
                        slot(2, hover: champion(103), role: .middle), slot(3, role: .bottom),
                        slot(4, hover: champion(412), role: .utility),
                    ],
                    enemies: [slot(5), slot(6), slot(7), slot(8), slot(9)],
                    bans: [], pickable: pickable, phase: .planning,
                    isMyTurnToPick: false, isMyTurnToBan: false))
    }

    @Test func mapsABanPickSessionInProgress() throws {
        let draft = try context(decodeCase("ban-pick-in-progress"))
        #expect(draft.phase == .banPick)
        #expect(draft.myRole == .middle)
        #expect(
            draft.allies == [
                slot(0, champion: champion(266), role: .top),
                slot(1, hover: champion(64), role: .jungle),
                slot(2, hover: champion(103), role: .middle),
            ])
        #expect(draft.enemies == [slot(5, champion: champion(238)), slot(6)])
        #expect(draft.bans == [champion(157), champion(555)])
        #expect(draft.isMyTurnToPick)
        #expect(!draft.isMyTurnToBan)
    }

    @Test func blindPickLeavesEveryRoleUnassigned() throws {
        let draft = try context(decodeCase("blind-pick"))
        #expect(draft.myRole == nil)
        #expect(draft.allies == [slot(0), slot(1, champion: champion(22))])
        #expect(draft.allies.allSatisfy { $0.roleConfidence == 0 })
        #expect(draft.isMyTurnToPick)
    }

    @Test func alliesAssignedByTheClientHaveFullConfidence() throws {
        let draft = try context(
            session(myTeam: [Member(cellId: 2, assignedPosition: .role(.bottom))]))
        #expect(draft.allies.map(\.roleConfidence) == [1])
    }

    @Test func enemiesWithoutAClientPositionAreUnassignedWithZeroConfidence() throws {
        let draft = try context(
            session(theirTeam: [Member(cellId: 7, championId: champion(238))]))
        #expect(draft.enemies == [slot(7, champion: champion(238))])
        #expect(draft.enemies[0].roleConfidence == 0)
    }

    @Test func anEnemyPositionFromTheClientIsKept() throws {
        let draft = try context(
            session(theirTeam: [Member(cellId: 7, assignedPosition: .role(.middle))]))
        #expect(draft.enemies == [slot(7, role: .middle)])
    }

    @Test func anUnknownPositionMapsToNoRole() throws {
        let draft = try context(
            session(myTeam: [Member(cellId: 2, assignedPosition: .unknown("fill"))]))
        #expect(draft.myRole == nil)
        #expect(draft.allies == [slot(2)])
    }

    @Test func anInProgressPickShowingAChampionIsAHoverNotALock() throws {
        let draft = try context(
            session(
                myTeam: [Member(cellId: 2, championId: champion(103))],
                actions: [
                    [
                        action(
                            .pick, actor: 2, champion: champion(103), inProgress: true,
                            completed: false)
                    ]
                ]))
        #expect(draft.allies == [slot(2, hover: champion(103))])
    }

    @Test func aCompletedPickIsALock() throws {
        let draft = try context(
            session(
                myTeam: [Member(cellId: 2, championId: champion(103))],
                actions: [
                    [
                        action(
                            .pick, actor: 2, champion: champion(103), inProgress: false,
                            completed: true)
                    ]
                ]))
        #expect(draft.allies == [slot(2, champion: champion(103))])
    }

    @Test func aCompletedPickWithoutAChampionLocksTheMembersChampion() throws {
        let draft = try context(
            session(
                myTeam: [Member(cellId: 2, championId: champion(103))],
                actions: [[action(.pick, actor: 2, inProgress: false, completed: true)]]))
        #expect(draft.allies == [slot(2, champion: champion(103))])
    }

    @Test func aCellWithNoPickActionsFallsBackToItsChampionAsLocked() throws {
        let draft = try context(
            session(
                myTeam: [Member(cellId: 2, championId: champion(103))],
                theirTeam: [Member(cellId: 7, championId: champion(238))],
                actions: [
                    [
                        action(
                            .ban, actor: 2, champion: champion(10), inProgress: false,
                            completed: true)
                    ]
                ]))
        #expect(draft.allies == [slot(2, champion: champion(103))])
        #expect(draft.enemies == [slot(7, champion: champion(238))])
    }

    @Test func aPickIntentIsAHoverBeforeTheTurn() throws {
        let draft = try context(
            session(
                myTeam: [Member(cellId: 2, championPickIntent: champion(64))],
                actions: [[action(.pick, actor: 2, inProgress: false, completed: false)]]))
        #expect(draft.allies == [slot(2, hover: champion(64))])
    }

    @Test func theTurnHoverWinsOverThePickIntent() throws {
        let draft = try context(
            session(
                myTeam: [
                    Member(cellId: 2, championId: champion(103), championPickIntent: champion(64))
                ],
                actions: [
                    [
                        action(
                            .pick, actor: 2, champion: champion(103), inProgress: true,
                            completed: false)
                    ]
                ]))
        #expect(draft.allies == [slot(2, hover: champion(103))])
    }

    @Test func enemiesFollowTheirPickActions() throws {
        let draft = try context(
            session(
                theirTeam: [
                    Member(cellId: 5, championId: champion(238)),
                    Member(cellId: 6, championId: champion(51)),
                ],
                actions: [
                    [
                        action(
                            .pick, actor: 5, champion: champion(238), inProgress: false,
                            completed: true)
                    ],
                    [
                        action(
                            .pick, actor: 6, champion: champion(51), inProgress: true,
                            completed: false)
                    ],
                ]))
        #expect(draft.enemies == [slot(5, champion: champion(238)), slot(6, hover: champion(51))])
    }

    @Test func membersWithoutACellAreLeftOut() throws {
        let draft = try context(
            session(
                myTeam: [Member(cellId: 2), Member(championId: champion(22))],
                theirTeam: [Member(championId: champion(238)), Member(cellId: 7)]))
        #expect(draft.allies.map(\.cellId) == [2])
        #expect(draft.enemies.map(\.cellId) == [7])
    }

    @Test func bansJoinBothTeamsAndCompletedBanActions() throws {
        let draft = try context(
            session(
                actions: [
                    [
                        action(
                            .ban, actor: 0, champion: champion(10), inProgress: false,
                            completed: true),
                        action(
                            .ban, actor: 5, champion: champion(20), inProgress: true,
                            completed: false),
                        action(
                            .pick, actor: 1, champion: champion(30), inProgress: false,
                            completed: true),
                    ]
                ],
                bans: Session.Bans(
                    myTeamBans: [champion(1), champion(10)], theirTeamBans: [champion(2)])
            ))
        #expect(draft.bans == [champion(1), champion(2), champion(10)])
    }

    @Test func itIsMyTurnToPickWhenMyPickIsInProgress() throws {
        let draft = try context(
            session(actions: [[action(.pick, actor: 2, inProgress: true, completed: false)]]))
        #expect(draft.isMyTurnToPick)
        #expect(!draft.isMyTurnToBan)
    }

    @Test func itIsNotMyTurnToPickWhenAnotherCellIsPicking() throws {
        let draft = try context(
            session(actions: [
                [action(.pick, actor: 1, inProgress: true, completed: false)],
                [action(.pick, actor: 2, inProgress: false, completed: false)],
            ]))
        #expect(!draft.isMyTurnToPick)
    }

    @Test func itIsNotMyTurnOnceMyActionIsCompleted() throws {
        let draft = try context(
            session(actions: [
                [action(.ban, actor: 2, inProgress: true, completed: true)],
                [action(.pick, actor: 2, inProgress: true, completed: true)],
            ]))
        #expect(!draft.isMyTurnToPick)
        #expect(!draft.isMyTurnToBan)
    }

    @Test func itIsMyTurnToBanWhenMyBanIsInProgress() throws {
        let draft = try context(
            session(actions: [[action(.ban, actor: 2, inProgress: true, completed: false)]]))
        #expect(draft.isMyTurnToBan)
        #expect(!draft.isMyTurnToPick)
    }

    @Test func itIsNotMyTurnToBanWhenAnotherCellIsBanning() throws {
        let draft = try context(
            session(actions: [[action(.ban, actor: 0, inProgress: true, completed: false)]]))
        #expect(!draft.isMyTurnToBan)
    }

    @Test(arguments: [
        (Session.Timer.Phase.planning, DraftPhase.planning),
        (.banPick, .banPick),
        (.finalization, .finalization),
    ])
    func mapsEachKnownPhase(_ phase: ChampSelectSession.Timer.Phase, _ expected: DraftPhase) throws
    {
        #expect(try context(session(phase: phase)).phase == expected)
    }

    @Test func noLocalPlayerCellYieldsNoContext() {
        #expect(
            session(localPlayerCellId: nil).draftContext(queue: .aram, patch: patch, pickable: [])
                == nil)
    }

    @Test func aLocalCellMissingFromMyTeamYieldsNoContext() {
        let draft = session(localPlayerCellId: 3, myTeam: [Member(cellId: 2)])
            .draftContext(queue: .aram, patch: patch, pickable: [])
        #expect(draft == nil)
    }

    @Test func aMissingTimerYieldsNoContext() {
        let draft = Session(localPlayerCellId: 2, myTeam: [Member(cellId: 2)])
            .draftContext(queue: .aram, patch: patch, pickable: [])
        #expect(draft == nil)
    }

    @Test func aMissingPhaseYieldsNoContext() {
        #expect(session(phase: nil).draftContext(queue: .aram, patch: patch, pickable: []) == nil)
    }

    @Test func anUnknownPhaseYieldsNoContext() {
        let draft = session(phase: .unknown("GAME_STARTING"))
            .draftContext(queue: .aram, patch: patch, pickable: [])
        #expect(draft == nil)
    }
}
