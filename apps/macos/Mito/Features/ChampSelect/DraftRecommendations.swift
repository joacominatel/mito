import Foundation
import MitoCore
import MitoEngine

/// What the personal layer knows, read once per champ select (§19.1). Mastery comes live from
/// the client; the rest from the personal store.
struct PersonalInputs: Hashable {
    var matches: [MyMatch] = []
    var pool: [PoolEntry] = []
    var overrides: [ChampionOverride] = []
    var masteryPoints: [ChampionID: Int] = [:]
}

/// The "Recomendados" column (§20.1), suggestions only: nothing here picks or bans (§5).
enum RecommendationList: Equatable {
    enum Unavailable: Equatable {
        /// No snapshot open: the degraded mode of §20.3.
        case noSnapshot
        /// ARAM: no role to score.
        case noRole
        /// The setting for this list is off (§21.3).
        case disabled
    }

    case unavailable(Unavailable)
    case picks([PickRecommendation])
    case bans([BanRecommendation])

    /// One ranked champion as the column draws it.
    struct Row: Identifiable, Equatable {
        let id: ChampionID
        /// Winrate points; a ban ranks by `presencia · amenaza`, which is not, so it has none.
        let score: Double?
        let confidence: SampleLevel
        let reasons: [Reason]
    }

    var isBans: Bool {
        if case .bans = self { true } else { false }
    }

    var rows: [Row] {
        switch self {
        case .unavailable: []
        case .picks(let picks):
            picks.map {
                Row(
                    id: $0.champion, score: $0.score, confidence: $0.confidence, reasons: $0.reasons
                )
            }
        case .bans(let bans):
            bans.map {
                Row(id: $0.champion, score: nil, confidence: $0.confidence, reasons: $0.reasons)
            }
        }
    }
}

/// Feeds the §18.3 and §18.5 engines from the draft, the settings, and the personal layer.
enum DraftRecommendations {
    /// "Mi pool" also takes a champion with this many of the user's games in the role (§18.3).
    static let poolMinimumGames = 5

    static func list(
        for draft: DraftContext, role: Role?, isBanPhase: Bool, settings: ChampSelectSettings,
        stats: some StatsProvider, personal: PersonalInputs, now: Date
    ) -> RecommendationList {
        guard stats.meta != nil else { return .unavailable(.noSnapshot) }
        guard let role else { return .unavailable(.noRole) }
        let pool = pool(for: role, personal: personal)

        if isBanPhase {
            guard settings.banRecommendations else { return .unavailable(.disabled) }
            return .bans(
                BanScoring.recommendations(for: draft, role: role, myPicks: pool, stats: stats))
        }
        guard settings.pickRecommendations else { return .unavailable(.disabled) }
        return .picks(
            PickScoring.recommendations(
                for: draft, role: role, mode: settings.candidates, pool: Set(pool),
                owned: draft.pickable, stats: stats,
                weights: PickWeights(metaComfortBalance: settings.metaComfortBalance),
                personal: personalTerms(personal, pool: pool, stats: stats, now: now)))
    }

    /// Blind pick's default (§20.3): the role with most of the user's games on the champion
    /// they locked or hover, else the role with the largest declared pool, else MIDDLE. Ties go
    /// to the role declared first.
    static func blindRole(for draft: DraftContext, personal: PersonalInputs) -> Role {
        let me = draft.allies.first { $0.cellId == draft.myCellId }
        if let champion = me?.champion ?? me?.hover {
            var games: [Role: Int] = [:]
            for match in personal.matches where match.champion == champion {
                if let role = match.role { games[role, default: 0] += 1 }
            }
            if let role = mostCommon(games) { return role }
        }
        var declared: [Role: Int] = [:]
        for entry in personal.pool { declared[entry.role, default: 0] += 1 }
        return mostCommon(declared) ?? .middle
    }

    private static func mostCommon(_ counts: [Role: Int]) -> Role? {
        Role.allCases.filter { counts[$0, default: 0] > 0 }
            .max { counts[$0, default: 0] < counts[$1, default: 0] }
    }

    /// The role's declared pool by priority, then champions with `poolMinimumGames` games there
    /// by games; an exclusion override removes either (§17).
    static func pool(for role: Role, personal: PersonalInputs) -> [ChampionID] {
        let excluded = Set(
            personal.overrides.filter { $0.role == role && $0.isExcludedFromPool }.map(\.champion))
        let declared = personal.pool.filter { $0.role == role }
            .sorted { $0.priority < $1.priority }
            .map(\.champion)
        var games: [ChampionID: Int] = [:]
        for match in personal.matches where match.role == role {
            games[match.champion, default: 0] += 1
        }
        let played = games.filter { $0.value >= poolMinimumGames }
            .sorted { (-$0.value, $0.key.rawValue) < (-$1.value, $1.key.rawValue) }
            .map(\.key)
        var seen: Set<ChampionID> = []
        return (declared + played).filter { !excluded.contains($0) && seen.insert($0).inserted }
    }

    /// `nil` for every champion without history, so the personal term is 0 (§18.3). `pool` is
    /// the scored role's, in order: the comfort reason's rank.
    static func personalTerms(
        _ personal: PersonalInputs, pool: [ChampionID], stats: some StatsProvider, now: Date
    ) -> (ChampionID, Role) -> PersonalTerm? {
        guard !personal.matches.isEmpty else { return { _, _ in nil } }
        return { champion, role in
            PersonalTerm(
                PersonalScoring.score(
                    champion: champion, role: role, matches: personal.matches,
                    pool: personal.pool, overrides: personal.overrides,
                    masteryPoints: personal.masteryPoints, stats: stats, now: now),
                poolRank: pool.firstIndex(of: champion).map { $0 + 1 })
        }
    }
}
