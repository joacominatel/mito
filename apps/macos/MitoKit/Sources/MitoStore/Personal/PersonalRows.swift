import Foundation
import GRDB
import MitoCore

/// Row and column encodings of the personal database, pinned in §17's decision list.
enum PersonalRows {
    /// A stored value outside the §17 encoding.
    struct OutOfContract: Error {}

    enum Match {
        static func replace(_ match: MyMatch, in db: Database) throws {
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO my_matches (
                        game_id, queue_id, patch, played_at, champion_id, role, win, kills, deaths,
                        assists, cs, duration_s, opp_champion_id, spell1, spell2, perks, items
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    match.game.rawValue, match.queue.rawValue, match.patch.rawValue,
                    milliseconds(match.playedAt), match.champion.rawValue, match.role?.rawValue,
                    match.win, match.kills, match.deaths, match.assists, match.cs,
                    match.durationSeconds, match.opponent?.rawValue, match.spells.first.rawValue,
                    match.spells.second.rawValue, try json(match.perks.map(\.rawValue)),
                    try json(match.items.map(\.rawValue)),
                ])
            try db.execute(
                sql: "DELETE FROM my_match_participants WHERE game_id = ?",
                arguments: [match.game.rawValue])
            for (slot, participant) in match.participants.enumerated() {
                try db.execute(
                    sql: """
                        INSERT INTO my_match_participants (game_id, slot, champion_id, is_enemy, role)
                        VALUES (?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        match.game.rawValue, slot, participant.champion.rawValue,
                        participant.isEnemy, participant.role?.rawValue,
                    ])
            }
        }

        static func fetch(_ query: MyMatchQuery, in db: Database) throws -> [MyMatch] {
            var conditions: [String] = []
            var arguments = StatementArguments()
            if let champion = query.champion {
                conditions.append("champion_id = ?")
                arguments += [champion.rawValue]
            }
            if let role = query.role {
                conditions.append("role = ?")
                arguments += [role.rawValue]
            }
            if let patch = query.patch {
                conditions.append("patch = ?")
                arguments += [patch.rawValue]
            }
            var selection =
                conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
            selection += " ORDER BY played_at DESC, game_id DESC"
            if let limit = query.limit {
                selection += " LIMIT ?"
                arguments += [max(0, limit)]
            }

            var participants: [Int: [MyMatchParticipant]] = [:]
            for row in try Row.fetchAll(
                db,
                sql: """
                    SELECT game_id, champion_id, is_enemy, role FROM my_match_participants
                    WHERE game_id IN (SELECT game_id FROM my_matches \(selection))
                    ORDER BY game_id, slot
                    """,
                arguments: arguments)
            {
                participants[try row.decode(forColumn: "game_id"), default: []].append(
                    MyMatchParticipant(
                        champion: ChampionID(rawValue: try row.decode(forColumn: "champion_id")),
                        isEnemy: try row.decode(forColumn: "is_enemy"),
                        role: try optionalRole(row)))
            }

            return try Row.fetchAll(
                db, sql: "SELECT * FROM my_matches \(selection)", arguments: arguments
            )
            .map { row in
                let game: Int = try row.decode(forColumn: "game_id")
                return MyMatch(
                    game: GameID(rawValue: game),
                    queue: QueueID(rawValue: try row.decode(forColumn: "queue_id")),
                    patch: Patch(rawValue: try row.decode(forColumn: "patch")),
                    playedAt: date(milliseconds: try row.decode(forColumn: "played_at")),
                    champion: ChampionID(rawValue: try row.decode(forColumn: "champion_id")),
                    role: try optionalRole(row),
                    win: try row.decode(forColumn: "win"),
                    kills: try row.decode(forColumn: "kills"),
                    deaths: try row.decode(forColumn: "deaths"),
                    assists: try row.decode(forColumn: "assists"),
                    cs: try row.decode(forColumn: "cs"),
                    durationSeconds: try row.decode(forColumn: "duration_s"),
                    opponent: (try row.decode(Int?.self, forColumn: "opp_champion_id")).map(
                        ChampionID.init),
                    spells: SpellPair(
                        first: SummonerSpellID(rawValue: try row.decode(forColumn: "spell1")),
                        second: SummonerSpellID(rawValue: try row.decode(forColumn: "spell2"))),
                    perks: try decodeJSON([Int].self, row.decode(forColumn: "perks")).map(
                        PerkID.init),
                    items: try decodeJSON([Int].self, row.decode(forColumn: "items")).map(
                        ItemID.init),
                    participants: participants[game] ?? [])
            }
        }
    }

    static func arguments(for override: ChampionOverride) throws -> StatementArguments {
        [
            override.champion.rawValue, override.role.rawValue, override.runeMode.rawValue,
            try override.fixedPage.map { try json(RunePageJSON($0)) },
            override.spellMode.rawValue,
            try override.fixedSpells.map { try json([$0.first.rawValue, $0.second.rawValue]) },
            override.itemMode.rawValue,
            try override.fixedItems.map { try json(ItemSetJSON($0)) },
            override.isFavorite, override.isExcludedFromPool,
        ]
    }

    static func championOverride(_ row: Row) throws -> ChampionOverride {
        ChampionOverride(
            champion: ChampionID(rawValue: try row.decode(forColumn: "champion_id")),
            role: try role(row.decode(forColumn: "role")),
            runeMode: .init(rawValue: try row.decode(forColumn: "runes_mode")),
            fixedPage: try (row.decode(String?.self, forColumn: "fixed_page")).map {
                try decodeJSON(RunePageJSON.self, $0).value
            },
            spellMode: .init(rawValue: try row.decode(forColumn: "spells_mode")),
            fixedSpells: try (row.decode(String?.self, forColumn: "fixed_spells")).map {
                let ids = try decodeJSON([Int].self, $0)
                guard ids.count == 2 else { throw OutOfContract() }
                return SpellPair(
                    first: SummonerSpellID(rawValue: ids[0]),
                    second: SummonerSpellID(rawValue: ids[1]))
            },
            itemMode: .init(rawValue: try row.decode(forColumn: "items_mode")),
            fixedItems: try (row.decode(String?.self, forColumn: "fixed_items")).map {
                try decodeJSON(ItemSetJSON.self, $0).value
            },
            isFavorite: try row.decode(forColumn: "favorite"),
            isExcludedFromPool: try row.decode(forColumn: "banned_from_pool"))
    }

    static func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    static func date(milliseconds: Int64) -> Date {
        Date(timeIntervalSince1970: Double(milliseconds) / 1000)
    }

    private static func role(_ rawValue: String) throws -> Role {
        guard let role = Role(rawValue: rawValue) else { throw OutOfContract() }
        return role
    }

    private static func optionalRole(_ row: Row) throws -> Role? {
        try (row.decode(String?.self, forColumn: "role")).map(role)
    }

    private static func json(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    private static func decodeJSON<T: Decodable>(_ type: T.Type, _ text: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(text.utf8))
    }
}

extension PersonalRows {
    private struct RunePageJSON: Codable {
        let primaryStyle: Int
        let subStyle: Int
        let perks: [Int]

        init(_ page: RunePage) {
            primaryStyle = page.primaryStyle.rawValue
            subStyle = page.subStyle.rawValue
            perks = page.perks.map(\.rawValue)
        }

        var value: RunePage {
            RunePage(
                primaryStyle: PerkStyleID(rawValue: primaryStyle),
                subStyle: PerkStyleID(rawValue: subStyle), perks: perks.map(PerkID.init))
        }
    }

    private struct ItemSetJSON: Codable {
        struct Block: Codable {
            let title: String
            let items: [Item]
        }

        struct Item: Codable {
            let id: Int
            let count: Int
        }

        let blocks: [Block]

        init(_ set: ItemSet) {
            blocks = set.blocks.map { block in
                Block(
                    title: block.title,
                    items: block.items.map { Item(id: $0.id.rawValue, count: $0.count) })
            }
        }

        var value: ItemSet {
            ItemSet(
                blocks: blocks.map { block in
                    ItemSet.Block(
                        title: block.title,
                        items: block.items.map {
                            ItemSet.Block.Item(id: ItemID(rawValue: $0.id), count: $0.count)
                        })
                })
        }
    }
}
