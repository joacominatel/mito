import Foundation
public import MitoCore

/// One rune page from `GET /lol-perks/v1/pages`; only the fields the importer reads.
public struct PerkPage: Decodable, Hashable, Sendable {
    public let id: Int
    public let name: String?
    public let current: Bool?
    /// `false` for the client's default and recommended pages.
    public let isEditable: Bool?
    /// `false` for pages that do not take a custom page slot.
    public let isDeletable: Bool?
    public let primaryStyleId: PerkStyleID?
    public let subStyleId: PerkStyleID?
    /// LCU order, as in `RunePage.perks`.
    public let selectedPerkIds: [PerkID]?

    public init(
        id: Int, name: String? = nil, current: Bool? = nil, isEditable: Bool? = nil,
        isDeletable: Bool? = nil, primaryStyleId: PerkStyleID? = nil,
        subStyleId: PerkStyleID? = nil, selectedPerkIds: [PerkID]? = nil
    ) {
        self.id = id
        self.name = name
        self.current = current
        self.isEditable = isEditable
        self.isDeletable = isDeletable
        self.primaryStyleId = primaryStyleId
        self.subStyleId = subStyleId
        self.selectedPerkIds = selectedPerkIds
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, current, isEditable, isDeletable, primaryStyleId, subStyleId
        case selectedPerkIds
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        current = try container.decodeIfPresent(Bool.self, forKey: .current)
        isEditable = try container.decodeIfPresent(Bool.self, forKey: .isEditable)
        isDeletable = try container.decodeIfPresent(Bool.self, forKey: .isDeletable)
        // Read only to compare with what Mito sent, so a bad value must not drop the page.
        primaryStyleId = (try? container.decodeIfPresent(Int.self, forKey: .primaryStyleId))
            .map(PerkStyleID.init)
        subStyleId = (try? container.decodeIfPresent(Int.self, forKey: .subStyleId))
            .map(PerkStyleID.init)
        selectedPerkIds = (try? container.decodeIfPresent([Int].self, forKey: .selectedPerkIds))
            .map { $0.map(PerkID.init) }
    }

    /// The page's runes, or `nil` when the client left out either style or the perks.
    public var runePage: RunePage? {
        guard let primaryStyleId, let subStyleId, let selectedPerkIds else { return nil }
        return RunePage(primaryStyle: primaryStyleId, subStyle: subStyleId, perks: selectedPerkIds)
    }
}

/// `GET /lol-perks/v1/inventory`.
public struct PerkInventory: Decodable, Hashable, Sendable {
    /// Custom page slots the account owns.
    public let ownedPageCount: Int?

    public init(ownedPageCount: Int? = nil) {
        self.ownedPageCount = ownedPageCount
    }
}

/// `GET /lol-perks/v1/styles`, mapped to `MitoCore.PerkStyle`. Styles without an `id` are
/// skipped.
public struct PerkStyles: Decodable, Hashable, Sendable {
    public let styles: [PerkStyle]

    public init(styles: [PerkStyle]) {
        self.styles = styles
    }

    public init(from decoder: any Decoder) throws {
        styles = try LossyArray<StyleBody>(from: decoder).elements.map(\.style)
    }

    private struct StyleBody: Decodable {
        let style: PerkStyle

        private enum CodingKeys: String, CodingKey {
            case id, name, iconPath, slots
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            style = PerkStyle(
                id: PerkStyleID(rawValue: try container.decode(Int.self, forKey: .id)),
                name: (try? container.decodeIfPresent(String.self, forKey: .name)) ?? "",
                iconPath: (try? container.decodeIfPresent(String.self, forKey: .iconPath)) ?? "",
                slots: container.decodeLossyArray(SlotBody.self, forKey: .slots).map(\.slot))
        }
    }

    private struct SlotBody: Decodable {
        let slot: PerkStyle.Slot

        private enum CodingKeys: String, CodingKey {
            case type, perks
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            slot = PerkStyle.Slot(
                // A row without a type is skipped, as for perkstyles.json (§16.1).
                kind: PerkStyle.Slot.Kind(
                    lcuType: try container.decode(String.self, forKey: .type)),
                perks: container.decodeLossyArray(Int.self, forKey: .perks).map(PerkID.init))
        }
    }
}

extension LCUEndpoint where Response == [PerkPage] {
    /// Every page, including the client's non-editable default pages. Pages without an `id` are
    /// skipped.
    public static var perkPages: Self {
        Self(method: .get, path: "/lol-perks/v1/pages") {
            try JSONDecoder().decode(LossyArray<PerkPage>.self, from: $0).elements
        }
    }
}

extension LCUEndpoint where Response == PerkInventory {
    public static var perkInventory: Self {
        Self(method: .get, path: "/lol-perks/v1/inventory")
    }
}

extension LCUEndpoint where Response == PerkStyles {
    public static var perkStyles: Self {
        Self(method: .get, path: "/lol-perks/v1/styles")
    }
}

extension LCUEndpoint where Response == LCUNoContent {
    /// Creates a page and makes it the current one (`MITO_CONTEXT.md` §13.2).
    public static func createPerkPage(_ page: RunePage, name: String) throws(LCUError) -> Self {
        try Self(method: .post, path: "/lol-perks/v1/pages", json: PerkPageBody(page, name: name))
    }

    /// Overwrites page `id` and makes it the current one (`MITO_CONTEXT.md` §13.2).
    public static func updatePerkPage(id: Int, _ page: RunePage, name: String) throws(LCUError)
        -> Self
    {
        try Self(
            method: .put, path: "/lol-perks/v1/pages/\(id)", json: PerkPageBody(page, name: name))
    }
}

private struct PerkPageBody: Encodable {
    let name: String
    let primaryStyleId: Int
    let subStyleId: Int
    let selectedPerkIds: [Int]
    let current = true

    init(_ page: RunePage, name: String) {
        self.name = name
        primaryStyleId = page.primaryStyle.rawValue
        subStyleId = page.subStyle.rawValue
        selectedPerkIds = page.perks.map(\.rawValue)
    }
}
