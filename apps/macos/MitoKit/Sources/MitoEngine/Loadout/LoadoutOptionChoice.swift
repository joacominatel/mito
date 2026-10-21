import MitoCore

/// A snapshot row a loadout part chooses among.
protocol LoadoutOption {
    var games: Int { get }
    var wins: Int { get }
    /// The row's content; the lexicographically lower key wins a tie.
    var tieBreakKey: [Int] { get }
}

extension RunePageCandidate: LoadoutOption {
    var tieBreakKey: [Int] {
        [page.primaryStyle.rawValue, page.subStyle.rawValue] + page.perks.map(\.rawValue)
    }
}

extension SpellPairCandidate: LoadoutOption {
    var tieBreakKey: [Int] { [spellA.rawValue, spellB.rawValue] }
}

extension ItemBuildCandidate: LoadoutOption {
    var tieBreakKey: [Int] { items.map(\.rawValue) }
}

extension SkillOrderCandidate: LoadoutOption {
    var tieBreakKey: [Int] {
        let index = { (ability: SkillOrder.Ability) in
            SkillOrder.Ability.allCases.firstIndex(of: ability) ?? 0
        }
        return order.maxOrder.map(index) + [-1] + order.sequence.map(index)
    }
}

/// How a part ranks its options (`MITO_CONTEXT.md` §18.6–§18.9).
enum ChoiceRule {
    /// Highest smoothed winrate among options played in at least `percent` % of `games`.
    case highestWinrate(minimumUsagePercent: Int, of: Int)
    /// Most played among options at or above `wr_smoothed(champ, role)`, or among all if none is.
    case mostPlayedWithGoodWinrate
}

/// The (champ, role) a loadout is chosen for.
struct ChoiceContext {
    let meta: SnapshotMeta
    /// `wr_smoothed(champ, role)`, the prior every loadout winrate centers on.
    let baseline: Double
    /// Below the `champ_role` minimum every part is still chosen but marked below minimum.
    let isChampionRoleBelowMinimum: Bool

    init(meta: SnapshotMeta, row: ChampionRoleStats) {
        self.meta = meta
        baseline = meta.priors.championRoleWinrate(wins: row.wins, games: row.games)
        isChampionRoleBelowMinimum =
            meta.sampleLevel(.championRole, games: row.games) == .belowMinimum
    }

    /// Without `fallsBackToMostPlayed`, `nil` when no option passes: an adapted context backs
    /// off instead (§18.1).
    func choose<Option: LoadoutOption>(
        _ options: [Option], kind: SampleKind, rule: ChoiceRule, fallsBackToMostPlayed: Bool = true
    ) -> (option: Option, level: SampleLevel)? {
        let minimum = meta.thresholds[kind]?.minimum ?? 0
        let usable = options.filter { $0.games >= minimum }

        let pick: Option?
        switch rule {
        case .highestWinrate(let percent, let games):
            pick = usable.filter { $0.games * 100 >= percent * games }
                .max { isRanked($0, below: $1, by: { [winrate($0), Double($0.games)] }) }
        case .mostPlayedWithGoodWinrate:
            let good = usable.filter { winrate($0) >= baseline }
            pick = (good.isEmpty ? usable : good)
                .max { isRanked($0, below: $1, by: { [Double($0.games), winrate($0)] }) }
        }
        // §14.12: when nothing passes, the exporter keeps the most played option alone.
        let fallback =
            fallsBackToMostPlayed
            ? options.max(by: { isRanked($0, below: $1, by: { [Double($0.games)] }) }) : nil
        guard let chosen = pick ?? fallback else { return nil }
        return (chosen, level(kind, games: chosen.games))
    }

    func level(_ kind: SampleKind, games: Int) -> SampleLevel {
        // A file without this kind's threshold cannot vouch for the sample.
        let level = meta.sampleLevel(kind, games: games) ?? .usable
        return isChampionRoleBelowMinimum ? .belowMinimum : level
    }

    func winrate(wins: Int, games: Int) -> Double {
        meta.priors.loadoutWinrate(wins: wins, games: games, baseline: baseline)
    }

    private func winrate(_ option: some LoadoutOption) -> Double {
        winrate(wins: option.wins, games: option.games)
    }

    private func isRanked<Option: LoadoutOption>(
        _ lhs: Option, below rhs: Option, by metrics: (Option) -> [Double]
    ) -> Bool {
        let left = metrics(lhs)
        let right = metrics(rhs)
        if left != right { return left.lexicographicallyPrecedes(right) }
        return rhs.tieBreakKey.lexicographicallyPrecedes(lhs.tieBreakKey)
    }
}
