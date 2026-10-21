public import Foundation

/// The LCU `gameId`.
public struct GameID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
}

/// One of the user's own games: a `my_matches` row plus its `my_match_participants`
/// (`MITO_CONTEXT.md` §17). No account identifiers: the game ID is the key.
public struct MyMatch: Hashable, Sendable {
    public let game: GameID
    public let queue: QueueID
    public let patch: Patch
    public let playedAt: Date
    public let champion: ChampionID
    /// `nil` when the client reports no lane, as in ARAM.
    public let role: Role?
    public let win: Bool
    public let kills: Int
    public let deaths: Int
    public let assists: Int
    public let cs: Int
    public let durationSeconds: Int
    /// The enemy in the same role; `nil` when there is none or the role is unknown.
    public let opponent: ChampionID?
    /// Client slot order, `first` on D: the Flash position is detected from it (§21.4).
    public let spells: SpellPair
    public let perks: [PerkID]
    /// The final inventory in slot order, empty slots dropped.
    public let items: [ItemID]
    /// The other nine players.
    public let participants: [MyMatchParticipant]

    public init(
        game: GameID,
        queue: QueueID,
        patch: Patch,
        playedAt: Date,
        champion: ChampionID,
        role: Role?,
        win: Bool,
        kills: Int,
        deaths: Int,
        assists: Int,
        cs: Int,
        durationSeconds: Int,
        opponent: ChampionID?,
        spells: SpellPair,
        perks: [PerkID],
        items: [ItemID],
        participants: [MyMatchParticipant]
    ) {
        self.game = game
        self.queue = queue
        self.patch = patch
        self.playedAt = playedAt
        self.champion = champion
        self.role = role
        self.win = win
        self.kills = kills
        self.deaths = deaths
        self.assists = assists
        self.cs = cs
        self.durationSeconds = durationSeconds
        self.opponent = opponent
        self.spells = spells
        self.perks = perks
        self.items = items
        self.participants = participants
    }
}

/// A `my_match_participants` row. Champion, side and role only: never a player identity (§5).
public struct MyMatchParticipant: Hashable, Sendable {
    public let champion: ChampionID
    public let isEnemy: Bool
    public let role: Role?

    public init(champion: ChampionID, isEnemy: Bool, role: Role?) {
        self.champion = champion
        self.isEnemy = isEnemy
        self.role = role
    }
}

/// Every field is optional; an empty query matches every game.
public struct MyMatchQuery: Hashable, Sendable {
    public var champion: ChampionID?
    public var role: Role?
    public var patch: Patch?
    /// The most recent games only.
    public var limit: Int?

    public init(
        champion: ChampionID? = nil, role: Role? = nil, patch: Patch? = nil, limit: Int? = nil
    ) {
        self.champion = champion
        self.role = role
        self.patch = patch
        self.limit = limit
    }
}
