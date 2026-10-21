import LCUKit
import MitoCore
import Testing

private typealias Session = ChampSelectSession

private func champion(_ id: Int) -> ChampionID { ChampionID(rawValue: id) }

private func reads(_ scenario: String) throws -> [Session] {
    try Recording(scenario).bodies(at: LCUEndpoint.champSelectSession.path).map {
        try LCUEndpoint.champSelectSession.decode($0)
    }
}

/// Every live session but the closing `Delete`, in arrival order. REST reads carry no time.
private func live(_ scenario: String) throws -> [Session] {
    try Recording(scenario).events(on: .champSelectSession).filter { $0.eventType != .delete }
        .map { try Session($0) }
}

private func drafts(_ scenario: String) throws -> [DraftContext] {
    try live(scenario).map {
        try #require(
            $0.draftContext(queue: .normalDraft, patch: Patch(rawValue: "16.21"), pickable: []))
    }
}

private func mySlot(_ draft: DraftContext) throws -> DraftSlot {
    try #require(draft.allies.first { $0.cellId == draft.myCellId })
}

struct RecordedChampSelectTests {
    @Test(arguments: ["ready-check", "champ-select"])
    func everySessionPlacesTheLocalPlayerInCellTwoAmongTenCells(_ scenario: String) throws {
        let recorded = try reads(scenario) + live(scenario)
        #expect(!recorded.isEmpty)
        for session in recorded {
            #expect(session.localPlayerCellId == 2)
            #expect(session.myTeam.map(\.cellId) == [0, 1, 2, 3, 4])
            #expect(session.theirTeam.map(\.cellId) == [5, 6, 7, 8, 9])
        }
    }

    @Test func alliesCarryLowercasePositionsAndEnemiesNone() throws {
        let session = try #require(try live("champ-select").first)
        #expect(
            session.myTeam.map(\.assignedPosition) == [
                .role(.utility), .role(.jungle), .role(.middle), .role(.bottom), .role(.top),
            ])
        #expect(session.myTeam.map(\.team) == Array(repeating: 1, count: 5))
        #expect(
            session.theirTeam.map(\.assignedPosition) == Array(repeating: .unassigned, count: 5))
        #expect(session.theirTeam.map(\.team) == Array(repeating: 2, count: 5))
        #expect(session.myTeam[2].spell1Id == SummonerSpellID(rawValue: 14))
        #expect(session.myTeam[2].spell2Id == SummonerSpellID(rawValue: 4))
    }

    @Test func aNormalDraftHasTenSimultaneousBansARevealAndSnakePicks() throws {
        for session in try live("champ-select") {
            #expect(
                session.actions.map { $0.map(\.type) } == [
                    Array(repeating: .ban, count: 10), [.tenBansReveal], [.pick], [.pick, .pick],
                    [.pick, .pick], [.pick, .pick], [.pick, .pick], [.pick],
                ])
            #expect(session.actions[0].map(\.actorCellId) == Array(0...9))
            #expect(session.actions[1][0].actorCellId == -1)
        }
    }

    @Test func theTimerGoesFromPlanningToBanPick() throws {
        let phases = try live("champ-select").compactMap(\.timer?.phase)
        let changes = phases.enumerated().filter {
            $0.offset == 0 || phases[$0.offset - 1] != $0.element
        }
        .map(\.element)
        #expect(changes == [.planning, .banPick])
        #expect(try live("champ-select").first?.timer?.adjustedTimeLeftInPhase == 12000)
    }

    @Test func aPlanningHoverIsAPickIntentOutsideMyTurn() throws {
        let planning = try drafts("champ-select").filter { $0.phase == .planning }
        let hovered = try #require(try planning.first { try mySlot($0).hover != nil })
        #expect(try mySlot(hovered).hover == champion(266))
        #expect(try mySlot(hovered).champion == nil)
        #expect(!hovered.isMyTurnToPick)
    }

    @Test func myHoverOnMyTurnBecomesTheChampionOnlyOnceThePickLocks() throws {
        let recorded = try drafts("champ-select")
        let locked = try #require(try recorded.firstIndex { try mySlot($0).champion != nil })
        let before = recorded[locked - 1]
        #expect(before.isMyTurnToPick)
        #expect(try mySlot(before).champion == nil)
        #expect(try mySlot(before).hover == champion(711))
        #expect(!recorded[locked].isMyTurnToPick)
        #expect(try mySlot(recorded[locked]).champion == champion(711))
        #expect(try mySlot(recorded[locked]).hover == nil)
    }

    @Test func bansComeFromCompletedActionsAndASkippedBanIsNoBan() throws {
        let last = try #require(try live("champ-select").last)
        #expect(last.bans == Session.Bans())
        let skipped = try #require(last.actions[0].first { $0.actorCellId == 3 })
        #expect(skipped.completed == true)
        #expect(skipped.championId == nil)
        let draft = try #require(try drafts("champ-select").last)
        #expect(draft.bans == Set([35, 64, 7, 420, 122, 119, 800, 86, 268].map(champion)))
    }

    @Test func theClosingDeleteCarriesAnEmptySessionThatIsNoDraft() throws {
        let delete = try #require(
            try Recording("champ-select").events(on: .champSelectSession).last)
        #expect(delete.eventType == .delete)
        let session = try Session(delete)
        #expect(session.localPlayerCellId == -1)
        #expect(session.myTeam.isEmpty)
        #expect(session.timer?.phase == .unknown(""))
        #expect(
            session.draftContext(queue: .normalDraft, patch: Patch(rawValue: "16.21"), pickable: [])
                == nil)
    }

    @Test(arguments: ["ready-check", "champ-select"])
    func pickableChampionsDecodeAsOneSetOfRealIDs(_ scenario: String) throws {
        let bodies = try Recording(scenario).bodies(
            at: LCUEndpoint<Set<ChampionID>>.pickableChampionIDs.path)
        #expect(bodies.count == 1)
        for body in bodies {
            let pickable = try LCUEndpoint.pickableChampionIDs.decode(body)
            #expect(pickable.count == 173)
            #expect(pickable.allSatisfy { $0.rawValue > 0 })
        }
    }

    @Test func bannableChampionsDropTheClientsMinusOne() throws {
        let bodies = try Recording("champ-select").bodies(
            at: LCUEndpoint<Set<ChampionID>>.bannableChampionIDs.path)
        let counts = try bodies.map { try LCUEndpoint.bannableChampionIDs.decode($0).count }
        #expect(counts.first == 0)
        #expect(Set(counts) == [0, 173])
    }
}
