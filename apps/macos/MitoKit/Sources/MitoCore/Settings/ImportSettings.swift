/// `MITO_CONTEXT.md` §21.4.
public struct ImportSettings: Codable, Hashable, Sendable {
    public enum RuneMode: String, Codable, Hashable, Sendable {
        /// Adapted to the lane matchup.
        case adaptive
        case general
        case fixedPerChampion
    }

    public enum RunePageTarget: String, Codable, Hashable, Sendable {
        /// The single page named `Mito · …`.
        case mitoPage
        /// The page in `reservedRunePageID`.
        case reservedPage
        case currentPage
    }

    public enum FlashPosition: String, Codable, Hashable, Sendable {
        case d
        case f
        /// Detected from recent games.
        case auto
    }

    public var importRunes: Bool
    public var runeMode: RuneMode
    public var runePageTarget: RunePageTarget
    public var reservedRunePageID: Int?
    public var importSpells: Bool
    public var flashPosition: FlashPosition
    public var importItemSets: Bool
    public var cleanOldItemSets: Bool
    public var importOnHover: Bool
    public var reimportOnOpponentChange: Bool
    public var preserveManualChanges: Bool

    public init(
        importRunes: Bool = true,
        runeMode: RuneMode = .adaptive,
        runePageTarget: RunePageTarget = .mitoPage,
        reservedRunePageID: Int? = nil,
        importSpells: Bool = true,
        flashPosition: FlashPosition = .auto,
        importItemSets: Bool = true,
        cleanOldItemSets: Bool = true,
        importOnHover: Bool = false,
        reimportOnOpponentChange: Bool = true,
        preserveManualChanges: Bool = true
    ) {
        self.importRunes = importRunes
        self.runeMode = runeMode
        self.runePageTarget = runePageTarget
        self.reservedRunePageID = reservedRunePageID
        self.importSpells = importSpells
        self.flashPosition = flashPosition
        self.importItemSets = importItemSets
        self.cleanOldItemSets = cleanOldItemSets
        self.importOnHover = importOnHover
        self.reimportOnOpponentChange = reimportOnOpponentChange
        self.preserveManualChanges = preserveManualChanges
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self()
        importRunes = container.decode(.importRunes, default: defaults.importRunes)
        runeMode = container.decode(.runeMode, default: defaults.runeMode)
        runePageTarget = container.decode(.runePageTarget, default: defaults.runePageTarget)
        reservedRunePageID = container.decode(
            .reservedRunePageID, default: defaults.reservedRunePageID)
        importSpells = container.decode(.importSpells, default: defaults.importSpells)
        flashPosition = container.decode(.flashPosition, default: defaults.flashPosition)
        importItemSets = container.decode(.importItemSets, default: defaults.importItemSets)
        cleanOldItemSets = container.decode(.cleanOldItemSets, default: defaults.cleanOldItemSets)
        importOnHover = container.decode(.importOnHover, default: defaults.importOnHover)
        reimportOnOpponentChange = container.decode(
            .reimportOnOpponentChange, default: defaults.reimportOnOpponentChange)
        preserveManualChanges = container.decode(
            .preserveManualChanges, default: defaults.preserveManualChanges)
    }
}
