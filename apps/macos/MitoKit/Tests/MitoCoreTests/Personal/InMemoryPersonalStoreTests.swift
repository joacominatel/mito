import Foundation
import MitoCore
import MitoTestSupport
import Testing

struct InMemoryPersonalStoreTests {
    private let ahri = ChampionID(rawValue: 103)
    private let syndra = ChampionID(rawValue: 134)
    private let zed = ChampionID(rawValue: 238)

    private func match(
        _ id: Int, champion: ChampionID? = nil, role: Role? = .middle, patch: String = "16.21",
        day: Int = 0, win: Bool = true, participants: [MyMatchParticipant] = []
    ) -> MyMatch {
        MyMatch(
            game: GameID(rawValue: id), queue: QueueID(rawValue: 420),
            patch: Patch(rawValue: patch),
            playedAt: Date(timeIntervalSince1970: Double(day) * 86_400),
            champion: champion ?? ahri, role: role, win: win, kills: 7, deaths: 2, assists: 9,
            cs: 210, durationSeconds: 1_740, opponent: zed,
            spells: SpellPair(
                first: SummonerSpellID(rawValue: 4), second: SummonerSpellID(rawValue: 14)),
            perks: [8112, 8143, 8138, 8135, 8226, 8237, 5008, 5008, 5011].map(PerkID.init),
            items: [3020, 6655, 4645].map(ItemID.init), participants: participants)
    }

    private func logEntry(second: Int, part: ImportLogEntry.Part = .runes) -> ImportLogEntry {
        ImportLogEntry(
            timestamp: Date(timeIntervalSince1970: Double(second)), game: GameID(rawValue: 1),
            champion: ahri, part: part, outcome: .applied)
    }

    @Test func recordingAGameAgainReplacesItAndItsParticipants() async throws {
        let store = InMemoryPersonalStore()
        try await store.record([
            match(1, win: false, participants: [.init(champion: zed, isEnemy: true, role: .middle)])
        ])
        let replay = match(
            1, win: true, participants: [.init(champion: syndra, isEnemy: false, role: nil)])
        try await store.record([replay])

        #expect(try await store.matches(MyMatchQuery()) == [replay])
    }

    @Test func returnsGamesNewestFirst() async throws {
        let store = InMemoryPersonalStore(matches: [
            match(1, day: 1), match(3, day: 3), match(2, day: 2),
        ])
        let games = try await store.matches(MyMatchQuery()).map(\.game.rawValue)
        #expect(games == [3, 2, 1])
    }

    @Test func filtersByChampionAndRole() async throws {
        let store = InMemoryPersonalStore(matches: [
            match(1), match(2, role: .top), match(3, champion: syndra), match(4, role: nil),
        ])
        let games = try await store.matches(MyMatchQuery(champion: ahri, role: .middle))
        #expect(games.map(\.game.rawValue) == [1])
    }

    @Test func filtersByPatch() async throws {
        let store = InMemoryPersonalStore(matches: [
            match(1, patch: "16.20"), match(2, patch: "16.21"),
        ])
        let games = try await store.matches(MyMatchQuery(patch: Patch(rawValue: "16.20")))
        #expect(games.map(\.game.rawValue) == [1])
    }

    @Test func aLimitKeepsTheMostRecentGames() async throws {
        let store = InMemoryPersonalStore(matches: (1...5).map { match($0, day: $0) })
        let games = try await store.matches(MyMatchQuery(limit: 2))
        #expect(games.map(\.game.rawValue) == [5, 4])
    }

    @Test func settingAPoolReplacesItInOrderWithoutRepeats() async throws {
        let store = InMemoryPersonalStore()
        try await store.setPool([zed], for: .middle)
        try await store.setPool([syndra, ahri, syndra], for: .middle)

        #expect(
            try await store.pool(for: .middle) == [
                PoolEntry(role: .middle, champion: syndra, priority: 0),
                PoolEntry(role: .middle, champion: ahri, priority: 1),
            ])
    }

    @Test func eachRoleKeepsItsOwnPool() async throws {
        let store = InMemoryPersonalStore()
        try await store.setPool([ahri], for: .middle)
        try await store.setPool([zed], for: .top)

        #expect(try await store.pool(for: .middle).map(\.champion) == [ahri])
        #expect(try await store.pool(for: .jungle).isEmpty)
    }

    @Test func savingAnOverrideReplacesTheOneForItsChampionAndRole() async throws {
        let store = InMemoryPersonalStore()
        try await store.save(ChampionOverride(champion: ahri, role: .middle, isFavorite: true))
        let fixed = ChampionOverride(
            champion: ahri, role: .middle, spellMode: .fixed,
            fixedSpells: SpellPair(
                first: SummonerSpellID(rawValue: 4), second: SummonerSpellID(rawValue: 12)))
        try await store.save(fixed)

        #expect(try await store.overrides() == [fixed])
    }

    @Test func listsOverridesByChampionThenRole() async throws {
        let store = InMemoryPersonalStore(overrides: [
            ChampionOverride(champion: syndra, role: .middle),
            ChampionOverride(champion: ahri, role: .middle),
            ChampionOverride(champion: ahri, role: .top),
        ])
        let keys = try await store.overrides().map { "\($0.champion.rawValue)-\($0.role.rawValue)" }
        #expect(keys == ["103-TOP", "103-MIDDLE", "134-MIDDLE"])
    }

    @Test func deletesOnlyTheGivenOverride() async throws {
        let store = InMemoryPersonalStore(overrides: [
            ChampionOverride(champion: ahri, role: .middle),
            ChampionOverride(champion: ahri, role: .top),
        ])
        try await store.deleteOverride(champion: ahri, role: .middle)
        try await store.deleteOverride(champion: zed, role: .middle)

        #expect(try await store.overrides().map(\.role) == [.top])
    }

    @Test func readsTheImportLogNewestFirstUpToTheLimit() async throws {
        let store = InMemoryPersonalStore()
        for entry in [logEntry(second: 1), logEntry(second: 3), logEntry(second: 2)] {
            try await store.appendImportLog(entry)
        }
        #expect(try await store.importLog(limit: 2) == [logEntry(second: 3), logEntry(second: 2)])
    }

    @Test func entriesWithTheSameTimestampReadLastAppendedFirst() async throws {
        let store = InMemoryPersonalStore(importLog: [
            logEntry(second: 5, part: .runes), logEntry(second: 5, part: .spells),
        ])
        #expect(try await store.importLog(limit: 10).map(\.part) == [.spells, .runes])
    }

    @Test func deletingEverythingEmptiesEveryTable() async throws {
        let store = InMemoryPersonalStore(
            matches: [match(1)], overrides: [ChampionOverride(champion: ahri, role: .middle)],
            importLog: [logEntry(second: 1)])
        try await store.setPool([ahri], for: .middle)

        try await store.deleteAll()

        #expect(try await store.matches(MyMatchQuery()).isEmpty)
        #expect(try await store.pool(for: .middle).isEmpty)
        #expect(try await store.overrides().isEmpty)
        #expect(try await store.importLog(limit: 10).isEmpty)
    }

    @Test func aFailingStoreThrowsAndChangesNothing() async throws {
        let store = InMemoryPersonalStore(matches: [match(1)])
        await store.setFailure(.writeFailed)

        await #expect(throws: PersonalStoreError.writeFailed) { try await store.deleteAll() }

        await store.setFailure(nil)
        #expect(try await store.matches(MyMatchQuery()).count == 1)
    }
}
