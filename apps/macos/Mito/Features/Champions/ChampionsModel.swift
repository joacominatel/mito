import Foundation
import MitoAssets
import MitoCore
import MitoEngine
import Observation

/// The patch tier list per role and the champion page (§22.2), read live from the open snapshot.
@Observable
final class ChampionsModel {
    var role: Role = .top
    /// The champion whose page is open; `nil` shows the tier list.
    var openedChampion: ChampionID?

    private let readStats: @MainActor () -> any StatsProvider
    private let readGameData: @MainActor () -> GameData?

    init(
        stats: @escaping @MainActor () -> any StatsProvider = { NoStats() },
        gameData: @autoclosure @escaping @MainActor () -> GameData? = nil
    ) {
        readStats = stats
        readGameData = gameData
    }

    /// `nil` when no snapshot is open: the tab shows its empty state.
    var meta: SnapshotMeta? { readStats().meta }

    /// The tier list of `role`: by tier, then smoothed winrate; rows without a tier go last.
    var rows: [ChampionRoleRow] {
        guard let meta else { return [] }
        return readStats().championRoleStats(in: role)
            .map {
                ChampionRoleRow(
                    champion: $0.key, name: championName($0.key), role: role, stats: $0.value,
                    meta: meta)
            }
            // §18.2: data under the minimum is not used, so it gets no row in the tier list.
            .filter { $0.tier != nil }
            .sorted(by: Self.tierListOrder)
    }

    /// One row per role the champion has stats in, in role order.
    func roles(of champion: ChampionID) -> [ChampionRoleRow] {
        guard let meta else { return [] }
        let stats = readStats()
        let name = championName(champion)
        return Role.allCases.compactMap { role in
            stats.championRoleStats(in: role)[champion].map {
                ChampionRoleRow(champion: champion, name: name, role: role, stats: $0, meta: meta)
            }
        }
    }

    func championName(_ id: ChampionID) -> String {
        if let name = readGameData()?.champion(id)?.name, !name.isEmpty { return name }
        return String(localized: "Campeón \(String(id.rawValue))", table: "Champions")
    }

    func run() async {}

    private static func tierListOrder(_ lhs: ChampionRoleRow, _ rhs: ChampionRoleRow) -> Bool {
        let left = lhs.tier.flatMap { Tier.allCases.firstIndex(of: $0) } ?? Tier.allCases.count
        let right = rhs.tier.flatMap { Tier.allCases.firstIndex(of: $0) } ?? Tier.allCases.count
        if left != right { return left < right }
        if lhs.winrate != rhs.winrate { return lhs.winrate > rhs.winrate }
        return lhs.champion.rawValue < rhs.champion.rawValue
    }

    private struct NoStats: StatsProvider {
        func roleGames(for champion: ChampionID) -> [Role: Int] { [:] }
    }
}

/// One (champion, role) of the tier list, every number derived by `MitoEngine` (§18.1, §18.2).
struct ChampionRoleRow: Identifiable, Hashable {
    let champion: ChampionID
    let name: String
    let role: Role
    /// `nil` below the `champ_role` minimum.
    let tier: Tier?
    /// `wr_smoothed(champ, role)`.
    let winrate: Double
    let pickRate: Double
    let games: Int
    /// Short of the `champ_role` "reliable" threshold, or no threshold in the file.
    let isLowSample: Bool

    var id: ChampionID { champion }

    init(
        champion: ChampionID, name: String, role: Role, stats: ChampionRoleStats,
        meta: SnapshotMeta
    ) {
        self.champion = champion
        self.name = name
        self.role = role
        tier = meta.tier(for: stats)
        winrate = meta.priors.championRoleWinrate(wins: stats.wins, games: stats.games)
        pickRate = meta.pickRate(games: stats.games)
        games = stats.games
        isLowSample = meta.sampleLevel(.championRole, games: stats.games)?.isLowSample ?? true
    }
}

extension Role {
    /// The role picker's labels.
    var tierListLabel: LocalizedStringResource {
        switch self {
        case .top: LocalizedStringResource("TOP", table: "Champions")
        case .jungle: LocalizedStringResource("JGL", table: "Champions")
        case .middle: LocalizedStringResource("MID", table: "Champions")
        case .bottom: LocalizedStringResource("ADC", table: "Champions")
        case .utility: LocalizedStringResource("SUP", table: "Champions")
        }
    }
}
