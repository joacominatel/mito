import Foundation
import LCUKit
import MitoCore
import MitoTestSupport
import Testing

private typealias Session = ChampSelectSession
private typealias Member = ChampSelectSession.Member
private typealias Action = ChampSelectSession.Action

private let cases = [
    "planning", "ban-pick-in-progress", "blind-pick", "unknown-values", "extra-fields",
    "missing-fields", "malformed-elements", "empty",
]

private func body(_ name: String) throws -> Data {
    try Data(contentsOf: Fixtures.url("lcu/cases/champ-select/\(name).json"))
}

private func decodeCase(_ name: String) throws -> Session {
    try LCUEndpoint.champSelectSession.decode(body(name))
}

private func champion(_ id: Int) -> ChampionID { ChampionID(rawValue: id) }
private func spell(_ id: Int) -> SummonerSpellID { SummonerSpellID(rawValue: id) }

struct ChampSelectSessionTests {
    @Test(arguments: cases)
    func theEventDataDecodesLikeTheRESTBody(_ name: String) throws {
        let event = LCUEvent(
            uri: "/lol-champ-select/v1/session", eventType: .update, data: try body(name))
        #expect(try Session(event) == decodeCase(name))
    }

    @Test func decodesAPlanningSession() throws {
        let session = try decodeCase("planning")
        #expect(session.localPlayerCellId == 2)
        #expect(session.timer == Session.Timer(phase: .planning, adjustedTimeLeftInPhase: 29500))
        #expect(session.myTeam.count == 5)
        #expect(
            session.myTeam[2]
                == Member(
                    cellId: 2, championPickIntent: champion(103),
                    assignedPosition: .role(.middle), spell1Id: spell(4), spell2Id: spell(14),
                    team: 1))
        #expect(session.myTeam.map(\.assignedPosition.role) == Role.allCases)
        #expect(session.theirTeam.map(\.cellId) == [5, 6, 7, 8, 9])
        #expect(session.actions.map(\.count) == [2, 1])
        #expect(session.bans == Session.Bans())
    }

    @Test func decodesABanPickSessionInProgress() throws {
        let session = try decodeCase("ban-pick-in-progress")
        #expect(session.timer?.phase == .banPick)
        #expect(session.myTeam[0].championId == champion(266))
        #expect(session.theirTeam[0] == Member(cellId: 5, championId: champion(238)))
        #expect(
            session.actions.map { $0.map(\.type) } == [
                [.ban, .ban], [.tenBansReveal], [.pick], [.pick], [.pick, .pick],
            ])
        #expect(
            session.actions[4][1]
                == Action(
                    id: 14, actorCellId: 2, championId: champion(103), type: .pick,
                    isInProgress: true, completed: false, isAllyAction: true))
        #expect(session.actions[0][1].isAllyAction == false)
    }

    @Test func zeroBansAreDropped() throws {
        #expect(
            try decodeCase("ban-pick-in-progress").bans
                == Session.Bans(myTeamBans: [champion(157)], theirTeamBans: [champion(555)]))
    }

    @Test func championZeroMeansNoChampion() throws {
        let session = try decodeCase("ban-pick-in-progress")
        #expect(session.myTeam[1].championId == nil)
        #expect(session.myTeam[0].championPickIntent == nil)
        #expect(session.theirTeam[1].championId == nil)
        #expect(session.actions[1][0].championId == nil)
    }

    @Test func minusOneMeansNoChampionInActionsMembersAndBans() throws {
        let json = #"""
            {"myTeam":[{"cellId":3,"championId":-1,"championPickIntent":-1,"spell1Id":-1}],
             "actions":[[{"id":3,"actorCellId":3,"championId":-1,"type":"ban","completed":true}]],
             "bans":{"myTeamBans":[-1,157],"theirTeamBans":[-1]}}
            """#
        let session = try LCUEndpoint.champSelectSession.decode(Data(json.utf8))
        #expect(session.myTeam == [Member(cellId: 3)])
        #expect(session.actions[0][0].championId == nil)
        #expect(session.bans == Session.Bans(myTeamBans: [champion(157)]))
    }

    @Test func blindPickHasNoRolesAndSpellZeroMeansNone() throws {
        let session = try decodeCase("blind-pick")
        #expect(session.myTeam.map(\.assignedPosition) == [.unassigned, .unassigned])
        #expect(session.myTeam.allSatisfy { $0.assignedPosition.role == nil })
        #expect(session.myTeam[0].spell1Id == nil)
        #expect(session.myTeam[0].spell2Id == nil)
        #expect(session.actions.flatMap { $0 }.allSatisfy { $0.type == .pick })
    }

    @Test func unknownValuesKeepTheirRawString() throws {
        let session = try decodeCase("unknown-values")
        #expect(session.actions[0][0].type == .unknown("vote_from_a_future_patch"))
        #expect(session.timer?.phase == .unknown("PHASE_FROM_A_FUTURE_PATCH"))
        #expect(session.myTeam[0].assignedPosition == .unknown("flex"))
        #expect(session.myTeam[0].assignedPosition.role == nil)
    }

    @Test func extraFieldsAndIdentityAreIgnored() throws {
        let session = try decodeCase("extra-fields")
        #expect(
            session
                == Session(
                    localPlayerCellId: 2,
                    myTeam: [
                        Member(
                            cellId: 2, championPickIntent: champion(103),
                            assignedPosition: .role(.middle), spell1Id: spell(4),
                            spell2Id: spell(14), team: 1)
                    ],
                    theirTeam: [Member(cellId: 7, championId: champion(238))],
                    actions: [
                        [
                            Action(
                                id: 11, actorCellId: 2, type: .pick, isInProgress: false,
                                completed: false, isAllyAction: true)
                        ]
                    ],
                    timer: Session.Timer(phase: .banPick, adjustedTimeLeftInPhase: 27000)))
    }

    @Test func noTextualFormCarriesIdentity() throws {
        let session = try decodeCase("extra-fields")
        let forms = [
            String(describing: session), String(reflecting: session),
            String(describing: Mirror(reflecting: session.myTeam[0]).children.map(\.label)),
        ]
        for form in forms {
            for identity in ["00000000-0000-0000-0000-00000000000", "Tester", "Rival", "TEST"] {
                #expect(!form.contains(identity))
            }
        }
    }

    @Test func missingFieldsDecodeAsNilOrEmpty() throws {
        #expect(
            try decodeCase("missing-fields")
                == Session(
                    myTeam: [Member(cellId: 2)],
                    actions: [[Action(id: 11, type: .pick)]],
                    timer: Session.Timer()))
    }

    @Test func anEmptyObjectIsAnEmptySession() throws {
        #expect(try decodeCase("empty") == Session())
    }

    @Test(arguments: [("27000", 27000), ("27000.6", 27001), ("\"soon\"", nil)] as [(String, Int?)])
    func aTimerKeepsTheSessionWhateverItsTimeLooksLike(time: String, expected: Int?) throws {
        let json =
            #"{"localPlayerCellId":2,"timer":{"phase":"BAN_PICK","adjustedTimeLeftInPhase":\#(time)}}"#
        let session = try LCUEndpoint.champSelectSession.decode(Data(json.utf8))
        #expect(session.localPlayerCellId == 2)
        #expect(session.timer?.adjustedTimeLeftInPhase == expected)
    }

    @Test func malformedElementsAreSkipped() throws {
        let session = try decodeCase("malformed-elements")
        #expect(session.myTeam.map(\.cellId) == [2])
        #expect(session.theirTeam.isEmpty)
        #expect(session.actions.map { $0.compactMap(\.id) } == [[1], [11]])
        #expect(session.bans.myTeamBans == [champion(157)])
        #expect(session.timer?.phase == .banPick)
    }

    @Test func nullCollectionsDecodeAsEmpty() throws {
        let json =
            #"{"myTeam":null,"theirTeam":null,"actions":null,"bans":{"myTeamBans":null,"theirTeamBans":null}}"#
        #expect(try LCUEndpoint.champSelectSession.decode(Data(json.utf8)) == Session())
    }

    @Test func nullScalarsDecodeAsNilAndKeepTheirElement() throws {
        let member =
            #"{"cellId":2,"championId":null,"championPickIntent":null,"assignedPosition":null,"spell1Id":null,"spell2Id":null,"team":null}"#
        let action =
            #"{"id":11,"actorCellId":null,"championId":null,"type":null,"isInProgress":null,"completed":null,"isAllyAction":null}"#
        let json =
            #"{"localPlayerCellId":null,"myTeam":[\#(member)],"actions":[[\#(action)]],"timer":{"phase":null,"adjustedTimeLeftInPhase":null}}"#
        #expect(
            try LCUEndpoint.champSelectSession.decode(Data(json.utf8))
                == Session(
                    myTeam: [Member(cellId: 2)], actions: [[Action(id: 11)]], timer: Session.Timer()
                ))
    }

    @Test(arguments: ["null", "[]", "\"ChampSelect\"", ""])
    func aBodyThatIsNotAnObjectIsADecodingError(_ json: String) {
        #expect {
            try LCUEndpoint.champSelectSession.decode(Data(json.utf8))
        } throws: { error in
            if case .decoding = error as? LCUError { true } else { false }
        }
    }

    @Test func aDeleteEventWithoutASessionIsADecodingError() {
        let event = LCUEvent(
            uri: "/lol-champ-select/v1/session", eventType: .delete, data: Data("null".utf8))
        #expect {
            try Session(event)
        } throws: { error in
            if case .decoding = error as? LCUError { true } else { false }
        }
    }
}

struct ChampSelectEnumTests {
    @Test(arguments: [
        ("ban", Action.Kind.ban), ("pick", .pick), ("ten_bans_reveal", .tenBansReveal),
        ("Pick", .unknown("Pick")),
    ])
    func actionTypeMatchesTheClientsSpelling(raw: String, kind: ChampSelectSession.Action.Kind) {
        #expect(Action.Kind(raw) == kind)
    }

    @Test(arguments: [
        ("PLANNING", Session.Timer.Phase.planning), ("BAN_PICK", .banPick),
        ("FINALIZATION", .finalization), ("GAME_STARTING", .unknown("GAME_STARTING")),
    ])
    func timerPhaseMatchesTheClientsSpelling(raw: String, phase: ChampSelectSession.Timer.Phase) {
        #expect(Session.Timer.Phase(raw) == phase)
    }

    @Test(arguments: [
        ("top", Session.AssignedPosition.role(.top)), ("jungle", .role(.jungle)),
        ("middle", .role(.middle)), ("bottom", .role(.bottom)), ("utility", .role(.utility)),
        ("", .unassigned), ("support", .unknown("support")),
    ])
    func assignedPositionMapsToARole(raw: String, position: ChampSelectSession.AssignedPosition) {
        #expect(Session.AssignedPosition(raw) == position)
    }
}

struct ChampSelectSessionEndpointTests {
    @Test func isAGetOnTheSessionPath() {
        let endpoint = LCUEndpoint.champSelectSession
        #expect(endpoint.method == .get)
        #expect(endpoint.path == "/lol-champ-select/v1/session")
        #expect(endpoint.body == nil)
    }

    @Test func sendsThroughAConnection() async throws {
        let connection = FakeLCUConnection(responses: [
            .init(method: .get, path: "/lol-champ-select/v1/session", body: try body("planning"))
        ])
        #expect(try await connection.send(.champSelectSession) == decodeCase("planning"))
    }
}
