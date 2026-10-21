import Foundation
public import MitoCore

/// A page of `GET /lol-match-history/v1/products/lol/current-summoner/matches`, newest first.
/// `games.games` is required; a game that cannot be mapped to a `MyMatch` is skipped.
public struct MatchHistoryPage: Decodable, Hashable, Sendable {
    public let matches: [MyMatch]

    private enum CodingKeys: String, CodingKey {
        case games
    }

    private struct GameList: Decodable {
        let games: LossyArray<MatchHistoryGame>
    }

    public init(from decoder: any Decoder) throws {
        matches = try decoder.container(keyedBy: CodingKeys.self)
            .decode(GameList.self, forKey: .games).games.elements.map(\.match)
    }
}

/// One LCU history game mapped to a `MyMatch`. Names and account IDs are never decoded; a PUUID
/// is only compared with the one in `userInfo[.localPUUID]`.
public struct MatchHistoryGame: Decodable, Hashable, Sendable {
    public let match: MyMatch

    private enum CodingKeys: String, CodingKey {
        case gameId, queueId, gameVersion, gameCreation, gameDuration, mapId
        case participants, participantIdentities
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let participants = container.decodeLossyArray(Participant.self, forKey: .participants)
        let identities = container.decodeLossyArray(
            Identity.self, forKey: .participantIdentities)
        // The history list carries only the current summoner's identity.
        let localID =
            identities.first(where: \.isLocalPlayer)?.participantId
            ?? (identities.count == 1 ? identities.first?.participantId : nil)
        guard let me = participants.first(where: { $0.participantId == localID }),
            let stats = me.stats, let spell1 = me.spell1Id, let spell2 = me.spell2Id
        else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "No local player"))
        }

        let mapID = try? container.decodeIfPresent(Int.self, forKey: .mapId)
        // Lanes exist only on Summoner's Rift (map 11); ARAM and other maps report noise.
        let hasLanes = mapID == nil || mapID == 11
        func role(_ participant: Participant) -> Role? { hasLanes ? participant.role : nil }

        let myRole = role(me)
        let others = participants.filter { $0.participantId != me.participantId }
        let opponents = others.filter {
            myRole != nil && $0.teamId != me.teamId && role($0) == myRole
        }
        let gameCreation = try container.decode(Int.self, forKey: .gameCreation)

        match = MyMatch(
            game: GameID(rawValue: try container.decode(Int.self, forKey: .gameId)),
            queue: QueueID(rawValue: try container.decode(Int.self, forKey: .queueId)),
            patch: try container.decode(GameVersion.self, forKey: .gameVersion).patch,
            playedAt: Date(timeIntervalSince1970: TimeInterval(gameCreation) / 1000),
            champion: me.champion,
            role: myRole,
            win: stats.win,
            kills: stats.kills,
            deaths: stats.deaths,
            assists: stats.assists,
            cs: stats.cs,
            durationSeconds: try container.decode(Int.self, forKey: .gameDuration),
            opponent: opponents.count == 1 ? opponents.first?.champion : nil,
            spells: SpellPair(first: spell1, second: spell2),
            perks: stats.perks,
            items: stats.items,
            participants: others.map {
                MyMatchParticipant(
                    champion: $0.champion, isEnemy: $0.teamId != me.teamId, role: role($0))
            })
    }
}

extension CodingUserInfoKey {
    /// `CurrentSummoner.puuid`, set by the history endpoints; failable only by signature.
    static let localPUUID = CodingUserInfoKey(rawValue: "localPUUID")
}

extension MatchHistoryGame {
    /// Only `participantId`, `teamId`, and a non-zero `championId` are required; what the local
    /// player needs beyond them is checked when mapping.
    private struct Participant: Decodable {
        let participantId: Int
        let teamId: Int
        let champion: ChampionID
        let spell1Id: SummonerSpellID?
        let spell2Id: SummonerSpellID?
        let stats: Stats?
        /// From `timeline.lane` and `timeline.role`.
        let role: Role?

        private enum CodingKeys: String, CodingKey {
            case participantId, teamId, championId, spell1Id, spell2Id, stats, timeline
        }

        private struct Timeline: Decodable {
            let lane: String?
            let role: String?
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            participantId = try container.decode(Int.self, forKey: .participantId)
            teamId = try container.decode(Int.self, forKey: .teamId)
            guard let champion = try container.decodeID(ChampionID.self, forKey: .championId)
            else {
                throw DecodingError.dataCorruptedError(
                    forKey: .championId, in: container, debugDescription: "No champion")
            }
            self.champion = champion
            spell1Id = try? container.decodeID(SummonerSpellID.self, forKey: .spell1Id)
            spell2Id = try? container.decodeID(SummonerSpellID.self, forKey: .spell2Id)
            stats = try? container.decodeIfPresent(Stats.self, forKey: .stats)
            let timeline = try? container.decodeIfPresent(Timeline.self, forKey: .timeline)
            role = Self.role(lane: timeline?.lane, role: timeline?.role)
        }

        private static func role(lane: String?, role: String?) -> Role? {
            switch (lane, role) {
            case ("TOP", _): .top
            case ("JUNGLE", _): .jungle
            case ("MIDDLE", _), ("MID", _): .middle
            case ("BOTTOM", "DUO_CARRY"), ("BOTTOM", "CARRY"), ("BOT", "DUO_CARRY"),
                ("BOT", "CARRY"):
                .bottom
            case ("BOTTOM", "DUO_SUPPORT"), ("BOTTOM", "SUPPORT"), ("BOT", "DUO_SUPPORT"),
                ("BOT", "SUPPORT"):
                .utility
            default: nil
            }
        }
    }

    private struct Stats: Decodable {
        let win: Bool
        let kills: Int
        let deaths: Int
        let assists: Int
        /// Lane minions plus jungle monsters.
        let cs: Int
        /// `perk0` to `perk5`, zeros dropped.
        let perks: [PerkID]
        /// `item0` to `item6`, empty slots dropped.
        let items: [ItemID]

        private struct Key: CodingKey {
            let stringValue: String
            var intValue: Int? { nil }
            init(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { nil }
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: Key.self)
            func int(_ name: String) throws -> Int {
                try container.decode(Int.self, forKey: Key(stringValue: name))
            }
            func slots(_ prefix: String, _ range: ClosedRange<Int>) -> [Int] {
                range.compactMap { slot in
                    try? container.decodeIfPresent(
                        Int.self, forKey: Key(stringValue: "\(prefix)\(slot)"))
                }.filter { $0 != 0 }
            }
            win = try container.decode(Bool.self, forKey: Key(stringValue: "win"))
            kills = try int("kills")
            deaths = try int("deaths")
            assists = try int("assists")
            cs = try int("totalMinionsKilled") + int("neutralMinionsKilled")
            perks = slots("perk", 0...5).map(PerkID.init(rawValue:))
            items = slots("item", 0...6).map(ItemID.init(rawValue:))
        }
    }

    private struct Identity: Decodable {
        let participantId: Int
        let isLocalPlayer: Bool

        private enum CodingKeys: String, CodingKey {
            case participantId, player
        }

        private enum PlayerKeys: String, CodingKey {
            case puuid
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            participantId = try container.decode(Int.self, forKey: .participantId)
            guard let key = CodingUserInfoKey.localPUUID,
                let localPUUID = decoder.userInfo[key] as? String, !localPUUID.isEmpty
            else {
                isLocalPlayer = false
                return
            }
            let puuid = try? container.nestedContainer(keyedBy: PlayerKeys.self, forKey: .player)
                .decodeIfPresent(String.self, forKey: .puuid)
            isLocalPlayer = puuid == localPUUID
        }
    }
}
