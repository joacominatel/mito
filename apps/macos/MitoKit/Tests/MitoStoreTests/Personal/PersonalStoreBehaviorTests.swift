import MitoCore
import MitoStore
import Testing

/// Runs against `InMemoryPersonalStore` and `PersonalDatabase`, so the two provably agree.
@Suite struct PersonalStoreBehaviorTests {
    private typealias Sample = PersonalSamples

    @Test(arguments: PersonalBackend.allCases)
    func anEmptyStoreReturnsNothing(_ backend: PersonalBackend) async throws {
        // Explicit `throws`: with only typed throws inside, `#expect` fails to compile.
        try await backend.withStore { (store: any PersonalStore) async throws in
            #expect(try await store.matches(MyMatchQuery()).isEmpty)
            #expect(try await store.pool(for: .middle).isEmpty)
            #expect(try await store.overrides().isEmpty)
            #expect(try await store.importLog(limit: 10).isEmpty)
        }
    }

    @Test(arguments: PersonalBackend.allCases)
    func aRecordedGameRoundTripsWhole(_ backend: PersonalBackend) async throws {
        try await backend.withStore { store in
            let ranked = Sample.match(game: 7_100_000_001)
            let aram = Sample.match(
                game: 7_100_000_002, role: nil, patch: "16.20", opponent: nil, participants: [])
            try await store.record([ranked, aram])

            #expect(try await store.matches(MyMatchQuery()) == [aram, ranked])
        }
    }

    @Test(arguments: PersonalBackend.allCases)
    func matchesComeNewestFirstWithTheHigherGameIDFirstOnATie(_ backend: PersonalBackend)
        async throws
    {
        try await backend.withStore { store in
            let oldest = Sample.match(game: 9, playedAt: 1_000)
            let tiedLow = Sample.match(game: 3, playedAt: 2_000)
            let tiedHigh = Sample.match(game: 4, playedAt: 2_000)
            let newest = Sample.match(game: 1, playedAt: 3_000)
            try await store.record([tiedLow, oldest, newest, tiedHigh])

            #expect(
                try await store.matches(MyMatchQuery()).map(\.game.rawValue) == [1, 4, 3, 9])
        }
    }

    @Test(arguments: PersonalBackend.allCases)
    func recordingAGameAgainReplacesItAndItsParticipants(_ backend: PersonalBackend) async throws {
        try await backend.withStore { store in
            try await store.record([Sample.match(game: 5)])
            let corrected = Sample.match(
                game: 5, champion: 4, participants: Array(Sample.participants.prefix(3)))
            try await store.record([corrected])

            #expect(try await store.matches(MyMatchQuery()) == [corrected])
        }
    }

    @Test(arguments: PersonalBackend.allCases)
    func repeatedChampionsRoundTripInSlotOrder(_ backend: PersonalBackend) async throws {
        try await backend.withStore { store in
            let ahri = ChampionID(rawValue: 103)
            let blindPick = Sample.match(
                game: 11, playedAt: 1_000,
                participants: [
                    .init(champion: ahri, isEnemy: false, role: .top),
                    .init(champion: ChampionID(rawValue: 64), isEnemy: false, role: .jungle),
                    .init(champion: ahri, isEnemy: true, role: .middle),
                ])
            let lux = ChampionID(rawValue: 99)
            let oneForAll = Sample.match(
                game: 12, playedAt: 2_000, champion: 99, role: nil, opponent: nil,
                participants: (0..<4).map { _ in .init(champion: lux, isEnemy: false, role: nil) }
                    + (0..<5).map { _ in
                        .init(champion: ChampionID(rawValue: 555), isEnemy: true, role: nil)
                    })
            try await store.record([blindPick, oneForAll])

            #expect(try await store.matches(MyMatchQuery()) == [oneForAll, blindPick])
        }
    }

    @Test(arguments: PersonalBackend.allCases)
    func queriesFilterByChampionRoleAndPatch(_ backend: PersonalBackend) async throws {
        try await backend.withStore { store in
            try await store.record([
                Sample.match(
                    game: 1, playedAt: 1_000, champion: 103, role: .middle, patch: "16.21"),
                Sample.match(game: 2, playedAt: 2_000, champion: 103, role: .top, patch: "16.20"),
                Sample.match(game: 3, playedAt: 3_000, champion: 84, role: .middle, patch: "16.21"),
                Sample.match(game: 4, playedAt: 4_000, champion: 103, role: nil, patch: "16.21"),
            ])
            func games(_ query: MyMatchQuery) async throws -> [Int] {
                try await store.matches(query).map(\.game.rawValue)
            }

            #expect(
                try await games(MyMatchQuery(champion: ChampionID(rawValue: 103))) == [4, 2, 1])
            #expect(try await games(MyMatchQuery(role: .middle)) == [3, 1])
            #expect(try await games(MyMatchQuery(patch: Patch(rawValue: "16.21"))) == [4, 3, 1])
            #expect(
                try await games(
                    MyMatchQuery(
                        champion: ChampionID(rawValue: 103), role: .middle,
                        patch: Patch(rawValue: "16.21"))) == [1])
            #expect(try await games(MyMatchQuery(role: .jungle)).isEmpty)
        }
    }

    @Test(arguments: PersonalBackend.allCases)
    func aLimitKeepsTheMostRecentMatchingGames(_ backend: PersonalBackend) async throws {
        try await backend.withStore { store in
            try await store.record(
                (1...5).map { Sample.match(game: $0, playedAt: Int64($0) * 1_000) })

            let recent = try await store.matches(MyMatchQuery(limit: 2))
            #expect(recent.map(\.game.rawValue) == [5, 4])
            #expect(recent.allSatisfy { $0.participants == Sample.participants })
            #expect(try await store.matches(MyMatchQuery(limit: 0)).isEmpty)
            #expect(try await store.matches(MyMatchQuery(limit: -1)).isEmpty)
        }
    }

    @Test(arguments: PersonalBackend.allCases)
    func thePoolComesInPriorityOrderAndARepeatKeepsItsFirstPosition(_ backend: PersonalBackend)
        async throws
    {
        try await backend.withStore { store in
            try await store.setPool([103, 7, 103, 84, 7].map(ChampionID.init), for: .middle)

            #expect(
                try await store.pool(for: .middle) == [
                    PoolEntry(role: .middle, champion: ChampionID(rawValue: 103), priority: 0),
                    PoolEntry(role: .middle, champion: ChampionID(rawValue: 7), priority: 1),
                    PoolEntry(role: .middle, champion: ChampionID(rawValue: 84), priority: 2),
                ])
        }
    }

    @Test(arguments: PersonalBackend.allCases)
    func settingAPoolReplacesOnlyThatRole(_ backend: PersonalBackend) async throws {
        try await backend.withStore { store in
            try await store.setPool([103, 7].map(ChampionID.init), for: .middle)
            try await store.setPool([86].map(ChampionID.init), for: .top)
            try await store.setPool([84].map(ChampionID.init), for: .middle)

            #expect(
                try await store.pool(for: .middle) == [
                    PoolEntry(role: .middle, champion: ChampionID(rawValue: 84), priority: 0)
                ])
            #expect(
                try await store.pool(for: .top) == [
                    PoolEntry(role: .top, champion: ChampionID(rawValue: 86), priority: 0)
                ])
            try await store.setPool([], for: .top)
            #expect(try await store.pool(for: .top).isEmpty)
        }
    }

    @Test(arguments: PersonalBackend.allCases)
    func overridesAreOrderedByChampionThenRoleOrder(_ backend: PersonalBackend) async throws {
        try await backend.withStore { store in
            for (champion, role) in [
                (103, Role.utility), (7, .middle), (103, .top), (103, .bottom),
            ] {
                try await store.save(
                    ChampionOverride(champion: ChampionID(rawValue: champion), role: role))
            }

            #expect(
                try await store.overrides().map { "\($0.champion.rawValue)-\($0.role.rawValue)" }
                    == [
                        "7-MIDDLE", "103-TOP", "103-BOTTOM", "103-UTILITY",
                    ])
        }
    }

    @Test(arguments: PersonalBackend.allCases)
    func savingAnOverrideReplacesTheOneForItsChampionAndRole(_ backend: PersonalBackend)
        async throws
    {
        try await backend.withStore { store in
            let other = ChampionOverride(champion: ChampionID(rawValue: 103), role: .top)
            try await store.save(other)
            try await store.save(
                ChampionOverride(champion: ChampionID(rawValue: 103), role: .middle))
            try await store.save(Sample.fullOverride)

            #expect(try await store.overrides() == [other, Sample.fullOverride])
        }
    }

    @Test(arguments: PersonalBackend.allCases)
    func deletingAnOverrideRemovesOnlyThatOneAndAMissingOneIsNotAnError(
        _ backend: PersonalBackend
    ) async throws {
        try await backend.withStore { store in
            let kept = ChampionOverride(champion: ChampionID(rawValue: 103), role: .top)
            try await store.save(kept)
            try await store.save(Sample.fullOverride)

            try await store.deleteOverride(champion: ChampionID(rawValue: 103), role: .middle)
            try await store.deleteOverride(champion: ChampionID(rawValue: 1), role: .jungle)

            #expect(try await store.overrides() == [kept])
        }
    }

    @Test(arguments: PersonalBackend.allCases)
    func theImportLogComesNewestFirstWithTheLaterAppendFirstOnATie(_ backend: PersonalBackend)
        async throws
    {
        try await backend.withStore { store in
            let first = Sample.logEntry(at: 1_000)
            let tiedEarlier = Sample.logEntry(at: 2_000, game: nil, part: .spells)
            let tiedLater = Sample.logEntry(at: 2_000, part: .items, detail: "no item set")
            let older = Sample.logEntry(at: 500, part: .unknown("skills"))
            for entry in [first, tiedEarlier, tiedLater, older] {
                try await store.appendImportLog(entry)
            }

            #expect(try await store.importLog(limit: 10) == [tiedLater, tiedEarlier, first, older])
            #expect(try await store.importLog(limit: 2) == [tiedLater, tiedEarlier])
            #expect(try await store.importLog(limit: 0).isEmpty)
            #expect(try await store.importLog(limit: -3).isEmpty)
        }
    }

    @Test(arguments: PersonalBackend.allCases)
    func deleteAllEmptiesEveryTable(_ backend: PersonalBackend) async throws {
        try await backend.withStore { store in
            try await store.record([Sample.match(game: 1)])
            try await store.setPool([ChampionID(rawValue: 103)], for: .middle)
            try await store.save(Sample.fullOverride)
            try await store.appendImportLog(Sample.logEntry(at: 1_000))

            try await store.deleteAll()

            #expect(try await store.matches(MyMatchQuery()).isEmpty)
            #expect(try await store.pool(for: .middle).isEmpty)
            #expect(try await store.overrides().isEmpty)
            #expect(try await store.importLog(limit: 10).isEmpty)
            try await store.record([Sample.match(game: 1)])
            #expect(try await store.matches(MyMatchQuery()) == [Sample.match(game: 1)])
        }
    }
}
