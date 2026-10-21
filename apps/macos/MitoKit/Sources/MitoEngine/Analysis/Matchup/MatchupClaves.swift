public import MitoCore

/// A hand-written tip from the locale's tips file (§14.12), already in the UI's language.
public struct CuratedTip: Hashable, Sendable {
    public let text: String
    /// The last patch the tip was checked against.
    public let reviewedPatch: Patch

    public init(text: String, reviewedPatch: Patch) {
        self.text = text
        self.reviewedPatch = reviewedPatch
    }
}

/// One line of "Claves" (§20.2): a curated tip, or a template filled from this matchup's data.
public enum Clave: Hashable, Sendable {
    case curated(CuratedTip)
    case generated(ClaveTemplate, sample: SampleLevel)
}

/// A data-driven clave; the app words it.
public enum ClaveTemplate: Hashable, Sendable {
    /// `matchup_delta`, at least `MatchupClaves.matchupMargin` either way.
    case matchup(delta: Double)
    /// Mean gold at 15 against the opponent, at least `MatchupClaves.goldMargin` either way.
    case laneGold(diff: Double)
    /// The first milestone one side reaches clearly before the other, at that side's second.
    case spike(SpikeComparison.Milestone, first: MatchupSide, atSeconds: Int)
    case powerCurve(stronger: MatchupSide, phase: CurveSummary.Phase)
}

enum MatchupClaves {
    /// In that order: the matchup, the lane, the first clear spike, the curves. Each only from
    /// data that passed its minimum.
    static func generated(
        matchup: SmoothedWinrate?, laneDiffs: LaneDiffs?, spikes: [SpikeComparison],
        curveSummary: CurveSummary?, champion: ChampionID
    ) -> [Clave] {
        var claves: [Clave] = []
        if let matchup, let delta = matchup.estimate?.delta, abs(delta) >= matchupMargin {
            claves.append(.generated(.matchup(delta: delta), sample: matchup.sample))
        }
        if let laneDiffs, let gold = laneDiffs.goldAt15, abs(gold) >= goldMargin {
            claves.append(.generated(.laneGold(diff: gold), sample: laneDiffs.sample))
        }
        if let spike = spikes.first(where: { $0.first != nil }), let first = spike.first,
            let seconds = first == .you ? spike.mine : spike.theirs
        {
            claves.append(
                .generated(
                    .spike(spike.milestone, first: first, atSeconds: seconds),
                    sample: spike.sample))
        }
        if let curveSummary, curveSummary.versus != nil {
            let stronger: MatchupSide = curveSummary.stronger == champion ? .you : .opponent
            claves.append(
                .generated(
                    .powerCurve(stronger: stronger, phase: curveSummary.phase),
                    sample: curveSummary.sample))
        }
        return claves
    }

    /// One winrate point, as the curve summary.
    static let matchupMargin = 0.01
    /// Less than a minion wave is noise in a 15-minute mean.
    static let goldMargin = 100.0
}
