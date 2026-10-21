import Foundation
import MitoCore
import MitoStore
import MitoTestSupport
import Testing

/// The two `PersonalStore`s that must agree: the fake is the behavior contract.
enum PersonalBackend: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case inMemory
    case sqlite

    var testDescription: String { rawValue }

    func withStore(_ body: (any PersonalStore) async throws -> Void) async throws {
        switch self {
        case .inMemory:
            try await body(InMemoryPersonalStore())
        case .sqlite:
            try await withTemporaryPersonalBase { base in
                try await body(
                    PersonalDatabase(
                        bundleIdentifier: PersonalSamples.bundleIdentifier, baseDirectory: base))
            }
        }
    }
}

enum PersonalSamples {
    static let bundleIdentifier = "com.joacominatel.mito.tests"

    /// Stored at millisecond precision, so samples are built from milliseconds.
    static func date(_ milliseconds: Int64) -> Date {
        Date(timeIntervalSince1970: Double(milliseconds) / 1000)
    }

    static let participants: [MyMatchParticipant] = [
        .init(champion: ChampionID(rawValue: 266), isEnemy: false, role: .top),
        .init(champion: ChampionID(rawValue: 64), isEnemy: false, role: .jungle),
        .init(champion: ChampionID(rawValue: 22), isEnemy: false, role: .bottom),
        .init(champion: ChampionID(rawValue: 412), isEnemy: false, role: .utility),
        .init(champion: ChampionID(rawValue: 86), isEnemy: true, role: .top),
        .init(champion: ChampionID(rawValue: 11), isEnemy: true, role: .jungle),
        .init(champion: ChampionID(rawValue: 7), isEnemy: true, role: .middle),
        .init(champion: ChampionID(rawValue: 51), isEnemy: true, role: nil),
        .init(champion: ChampionID(rawValue: 40), isEnemy: true, role: .utility),
    ]

    static func match(
        game: Int,
        playedAt milliseconds: Int64 = 1_760_000_000_123,
        champion: Int = 103,
        role: Role? = .middle,
        patch: String = "16.21",
        opponent: Int? = 7,
        participants: [MyMatchParticipant] = participants
    ) -> MyMatch {
        MyMatch(
            game: GameID(rawValue: game),
            queue: QueueID(rawValue: 420),
            patch: Patch(rawValue: patch),
            playedAt: date(milliseconds),
            champion: ChampionID(rawValue: champion),
            role: role,
            win: game.isMultiple(of: 2),
            kills: 7,
            deaths: 2,
            assists: 9,
            cs: 214,
            durationSeconds: 1_834,
            opponent: opponent.map(ChampionID.init),
            spells: SpellPair(
                first: SummonerSpellID(rawValue: 14), second: SummonerSpellID(rawValue: 4)),
            perks: [8112, 8139, 8138, 8135, 8226, 8210, 5008, 5008, 5011].map(PerkID.init),
            items: [3089, 3157, 3020, 4645].map(ItemID.init),
            participants: participants)
    }

    static let fullOverride = ChampionOverride(
        champion: ChampionID(rawValue: 103),
        role: .middle,
        runeMode: .fixed,
        fixedPage: RunePage(
            primaryStyle: PerkStyleID(rawValue: 8100), subStyle: PerkStyleID(rawValue: 8200),
            perks: [8112, 8139, 8138, 8135, 8226, 8210, 5008, 5008, 5011].map(PerkID.init)),
        spellMode: .fixed,
        fixedSpells: SpellPair(
            first: SummonerSpellID(rawValue: 4), second: SummonerSpellID(rawValue: 14)),
        itemMode: .fixedSet,
        fixedItems: ItemSet(blocks: [
            .init(
                title: "Start",
                items: [
                    .init(id: ItemID(rawValue: 1056)), .init(id: ItemID(rawValue: 2003), count: 2),
                ]),
            .init(title: "Core", items: [.init(id: ItemID(rawValue: 6655))]),
        ]),
        isFavorite: true,
        isExcludedFromPool: true)

    static func logEntry(
        at milliseconds: Int64, game: Int? = 7_100_000_001, part: ImportLogEntry.Part = .runes,
        detail: String? = nil
    ) -> ImportLogEntry {
        ImportLogEntry(
            timestamp: date(milliseconds), game: game.map(GameID.init),
            champion: ChampionID(rawValue: 103), part: part,
            outcome: detail == nil ? .applied : .skipped, detail: detail)
    }
}

func withTemporaryPersonalBase(_ body: (URL) async throws -> Void) async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "PersonalStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: directory) }
    try await body(directory)
}
