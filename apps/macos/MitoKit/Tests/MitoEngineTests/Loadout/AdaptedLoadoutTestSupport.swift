import MitoCore
import MitoTestSupport

let zed = ChampionID(rawValue: 238)

func lane(games: Int = 1_000, timelineGames: Int = 500) -> MatchupStats {
    MatchupStats(
        games: games, wins: games / 2, timelineGames: timelineGames, goldDiffAt15: nil,
        csDiffAt15: nil)
}

func final(_ item: Int, games: Int, wins: Int) -> FinalItemCandidate {
    FinalItemCandidate(item: ItemID(rawValue: item), games: games, wins: wins)
}

extension InMemoryStatsProvider {
    /// Rows of `champion` against the lane opponent; a `nil` matchup leaves `matchup_stats` empty.
    func versus(
        _ opponent: ChampionID = zed,
        champion: ChampionID = ahri,
        role: Role = .middle,
        matchup: MatchupStats? = lane(),
        runes: [RunePageCandidate] = [],
        spells: [SpellPairCandidate] = [],
        items: [ItemBuildCandidate] = []
    ) -> InMemoryStatsProvider {
        var stats = self
        stats.matchupsByChampion[champion, default: [:]][role, default: [:]][opponent] = matchup
        stats.opponentRunePagesByChampion[champion, default: [:]][role, default: [:]][opponent] =
            runes
        stats.opponentSpellPairsByChampion[champion, default: [:]][role, default: [:]][opponent] =
            spells
        stats.opponentItemBuildsByChampion[champion, default: [:]][role, default: [:]][opponent] =
            items
        return stats
    }

    /// `games` is `champ_vs_profile.games`; `nil` leaves the profile without that row.
    func against(
        _ profile: EnemyProfile,
        champion: ChampionID = ahri,
        role: Role = .middle,
        games: Int? = 1_000,
        runes: [RunePageCandidate] = [],
        finalItems: [FinalItemCandidate] = []
    ) -> InMemoryStatsProvider {
        var stats = self
        stats.profileStatsByChampion[champion, default: [:]][role, default: [:]][profile] =
            games.map { RelationStats(games: $0, wins: $0 / 2) }
        stats.profileRunePagesByChampion[champion, default: [:]][role, default: [:]][profile] =
            runes
        stats.profileFinalItemsByChampion[champion, default: [:]][role, default: [:]][profile] =
            finalItems
        return stats
    }

    /// The `'any'` rows of `item_vs_profile`.
    func baseline(
        _ items: [FinalItemCandidate], champion: ChampionID = ahri, role: Role = .middle
    ) -> InMemoryStatsProvider {
        var stats = self
        stats.baselineFinalItemsByChampion[champion, default: [:]][role] = items
        return stats
    }

    func flagged(_ flags: [ChampionID: Set<ChampionFlag>]) -> InMemoryStatsProvider {
        var stats = self
        stats.flagsByChampion.merge(flags) { _, new in new }
        return stats
    }
}
