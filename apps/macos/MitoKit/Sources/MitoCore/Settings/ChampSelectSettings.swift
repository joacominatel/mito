/// `MITO_CONTEXT.md` §21.3. Auto-pick and auto-ban stay off by default (Riot policy).
public struct ChampSelectSettings: Codable, Hashable, Sendable {
    public enum Candidates: String, Codable, Hashable, Sendable {
        case myPool
        case owned
        case all
    }

    public enum AutoBan: String, Codable, Hashable, Sendable {
        case off
        /// The first available champion in `autoBanList`.
        case list
        case recommended
    }

    public enum AutoPick: String, Codable, Hashable, Sendable {
        case off
        /// The first available champion in `autoPickList` for the assigned role.
        case listByRole
    }

    public var pickRecommendations: Bool
    public var banRecommendations: Bool
    public var candidates: Candidates
    /// 0 is pure meta, 1 is pure comfort.
    public var metaComfortBalance: Double
    public var autoHover: Bool
    public var autoBan: AutoBan
    public var autoBanList: [ChampionID]
    public var autoPick: AutoPick
    public var autoPickList: [Role: [ChampionID]]

    public init(
        pickRecommendations: Bool = true,
        banRecommendations: Bool = true,
        candidates: Candidates = .owned,
        metaComfortBalance: Double = 0.5,
        autoHover: Bool = false,
        autoBan: AutoBan = .off,
        autoBanList: [ChampionID] = [],
        autoPick: AutoPick = .off,
        autoPickList: [Role: [ChampionID]] = [:]
    ) {
        self.pickRecommendations = pickRecommendations
        self.banRecommendations = banRecommendations
        self.candidates = candidates
        self.metaComfortBalance = metaComfortBalance
        self.autoHover = autoHover
        self.autoBan = autoBan
        self.autoBanList = autoBanList
        self.autoPick = autoPick
        self.autoPickList = autoPickList
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self()
        pickRecommendations = container.decode(
            .pickRecommendations, default: defaults.pickRecommendations)
        banRecommendations = container.decode(
            .banRecommendations, default: defaults.banRecommendations)
        candidates = container.decode(.candidates, default: defaults.candidates)
        metaComfortBalance = container.decode(
            .metaComfortBalance, default: defaults.metaComfortBalance)
        autoHover = container.decode(.autoHover, default: defaults.autoHover)
        autoBan = container.decode(.autoBan, default: defaults.autoBan)
        autoBanList = container.decode(.autoBanList, default: defaults.autoBanList)
        autoPick = container.decode(.autoPick, default: defaults.autoPick)
        autoPickList = container.decode(.autoPickList, default: defaults.autoPickList)
    }
}
