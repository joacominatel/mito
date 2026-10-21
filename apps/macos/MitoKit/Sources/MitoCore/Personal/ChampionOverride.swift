/// A `champion_overrides` row: the user's manual choices for one (champion, role) (§21.5).
public struct ChampionOverride: Hashable, Sendable {
    /// Raw values are the `runes_mode` encoding.
    public enum RuneMode: RawRepresentable, Hashable, Sendable {
        /// Adapted to the lane matchup.
        case adaptive
        case general
        /// `fixedPage`.
        case fixed
        case unknown(String)

        public init(rawValue: String) {
            switch rawValue {
            case "adaptive": self = .adaptive
            case "general": self = .general
            case "fixed": self = .fixed
            default: self = .unknown(rawValue)
            }
        }

        public var rawValue: String {
            switch self {
            case .adaptive: "adaptive"
            case .general: "general"
            case .fixed: "fixed"
            case .unknown(let value): value
            }
        }
    }

    /// Raw values are the `spells_mode` encoding.
    public enum SpellMode: RawRepresentable, Hashable, Sendable {
        case recommended
        /// `fixedSpells`.
        case fixed
        case unknown(String)

        public init(rawValue: String) {
            switch rawValue {
            case "recommended": self = .recommended
            case "fixed": self = .fixed
            default: self = .unknown(rawValue)
            }
        }

        public var rawValue: String {
            switch self {
            case .recommended: "recommended"
            case .fixed: "fixed"
            case .unknown(let value): value
            }
        }
    }

    /// Raw values are the `items_mode` encoding.
    public enum ItemMode: RawRepresentable, Hashable, Sendable {
        case recommended
        case fixedSet
        /// No item set is imported.
        case skip
        case unknown(String)

        public init(rawValue: String) {
            switch rawValue {
            case "recommended": self = .recommended
            case "fixed_set": self = .fixedSet
            case "skip": self = .skip
            default: self = .unknown(rawValue)
            }
        }

        public var rawValue: String {
            switch self {
            case .recommended: "recommended"
            case .fixedSet: "fixed_set"
            case .skip: "skip"
            case .unknown(let value): value
            }
        }
    }

    public let champion: ChampionID
    public let role: Role
    public var runeMode: RuneMode
    public var fixedPage: RunePage?
    public var spellMode: SpellMode
    public var fixedSpells: SpellPair?
    public var itemMode: ItemMode
    /// The set imported when `itemMode` is `.fixedSet` (`fixed_items`).
    public var fixedItems: ItemSet?
    public var isFavorite: Bool
    public var isExcludedFromPool: Bool

    public init(
        champion: ChampionID,
        role: Role,
        runeMode: RuneMode = .adaptive,
        fixedPage: RunePage? = nil,
        spellMode: SpellMode = .recommended,
        fixedSpells: SpellPair? = nil,
        itemMode: ItemMode = .recommended,
        fixedItems: ItemSet? = nil,
        isFavorite: Bool = false,
        isExcludedFromPool: Bool = false
    ) {
        self.champion = champion
        self.role = role
        self.runeMode = runeMode
        self.fixedPage = fixedPage
        self.spellMode = spellMode
        self.fixedSpells = fixedSpells
        self.itemMode = itemMode
        self.fixedItems = fixedItems
        self.isFavorite = isFavorite
        self.isExcludedFromPool = isExcludedFromPool
    }
}
