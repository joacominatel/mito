public import MitoCore

/// When each side of the lane reaches a power spike, from `champion_profiles` (§17, §20.2).
public struct SpikeComparison: Hashable, Sendable {
    public enum Milestone: CaseIterable, Hashable, Sendable {
        /// `lvl6_s`.
        case levelSix
        /// `item1_s`.
        case firstItem
        /// `item2_s`.
        case secondItem
        /// `item3_s`.
        case thirdItem

        func seconds(in profile: ChampionProfile) -> Int? {
            switch self {
            case .levelSix: profile.levelSixSeconds
            case .firstItem: profile.firstItemSeconds
            case .secondItem: profile.secondItemSeconds
            case .thirdItem: profile.thirdItemSeconds
            }
        }
    }

    public let milestone: Milestone
    /// Median second; `nil` when unknown.
    public let mine: Int?
    public let theirs: Int?
    /// The lower sample of the sides shown.
    public let sample: SampleLevel

    /// Who gets there `margin` seconds or more before the other; `nil` when close or one-sided.
    public var first: MatchupSide? {
        guard let mine, let theirs, abs(mine - theirs) >= Self.marginSeconds else { return nil }
        return mine < theirs ? .you : .opponent
    }

    /// Medians a few seconds apart are noise.
    static let marginSeconds = 20

    /// In milestone order, those either side has. A profile below the `build_layer` minimum of
    /// timeline games, the denominator of these medians, counts as no profile.
    static func compare(mine: ChampionProfile?, theirs: ChampionProfile?, meta: SnapshotMeta)
        -> [SpikeComparison]
    {
        func usable(_ profile: ChampionProfile?) -> (ChampionProfile, SampleLevel)? {
            guard let profile,
                let level = meta.sampleLevel(.buildLayer, games: profile.timelineGames),
                level != .belowMinimum
            else { return nil }
            return (profile, level)
        }
        let mine = usable(mine)
        let theirs = usable(theirs)
        return Milestone.allCases.compactMap { milestone in
            let mySeconds = mine.flatMap { milestone.seconds(in: $0.0) }
            let theirSeconds = theirs.flatMap { milestone.seconds(in: $0.0) }
            let levels = [
                mySeconds == nil ? nil : mine?.1, theirSeconds == nil ? nil : theirs?.1,
            ].compactMap(\.self)
            guard let sample = levels.min() else { return nil }
            return SpikeComparison(
                milestone: milestone, mine: mySeconds, theirs: theirSeconds, sample: sample)
        }
    }
}
