import MitoCore

/// A rune page being built in the editor, row by typed row kind (§13.2), never by slot position.
struct RunePageDraft: Equatable {
    struct SecondaryPick: Equatable {
        /// The index among the sub style's `regular` rows.
        let row: Int
        let perk: PerkID
    }

    private(set) var primaryStyle: PerkStyleID?
    private(set) var subStyle: PerkStyleID?
    var keystone: PerkID?
    var primaryPerks: [PerkID?] = [nil, nil, nil]
    /// At most two, from different rows, oldest first: a third pick drops the oldest, as the
    /// client does.
    private(set) var secondary: [SecondaryPick] = []
    var shards: [PerkID?] = [nil, nil, nil]

    init() {}

    /// Places each perk where `styles` puts it; whatever no longer fits is left empty.
    init(_ page: RunePage, styles: [PerkStyle]) {
        guard page.perks.count == 9 else { return }
        let primary = styles.first { $0.id == page.primaryStyle }
        let sub = styles.first { $0.id == page.subStyle }
        primaryStyle = primary?.id
        subStyle = sub?.id == primaryStyle ? nil : sub?.id
        let keystones = primary?.rows(.keystone) ?? []
        let regular = primary?.rows(.regular) ?? []
        let shardRows = primary?.rows(.statMod) ?? []
        keystone = keystones.first.flatMap { $0.contains(page.perks[0]) ? page.perks[0] : nil }
        primaryPerks = (0..<3).map { Self.perk(page.perks[1 + $0], ifIn: regular, at: $0) }
        shards = (0..<3).map { Self.perk(page.perks[6 + $0], ifIn: shardRows, at: $0) }
        guard subStyle != nil, let secondaryRows = sub?.rows(.regular) else { return }
        for perk in page.perks[4...5] {
            if let row = secondaryRows.firstIndex(where: { $0.contains(perk) }) {
                setSecondaryPerk(perk, inRow: row)
            }
        }
    }

    /// Shards are kept when the new style has them in the same row; everything else of the
    /// old primary is cleared.
    mutating func setPrimaryStyle(_ id: PerkStyleID?, styles: [PerkStyle]) {
        guard id != primaryStyle else { return }
        primaryStyle = id
        keystone = nil
        primaryPerks = [nil, nil, nil]
        let shardRows = styles.first { $0.id == id }?.rows(.statMod) ?? []
        shards = shards.indices.map { Self.perk(shards[$0], ifIn: shardRows, at: $0) }
        if subStyle == id { setSubStyle(nil) }
    }

    mutating func setSubStyle(_ id: PerkStyleID?) {
        guard id != subStyle else { return }
        subStyle = id == primaryStyle ? nil : id
        secondary = []
    }

    func secondaryPerk(inRow row: Int) -> PerkID? {
        secondary.first { $0.row == row }?.perk
    }

    mutating func setSecondaryPerk(_ perk: PerkID?, inRow row: Int) {
        secondary.removeAll { $0.row == row }
        guard let perk else { return }
        if secondary.count == 2 { secondary.removeFirst() }
        secondary.append(SecondaryPick(row: row, perk: perk))
    }

    /// `nil` until every choice is made; a complete page still has to pass validation.
    var page: RunePage? {
        guard let primaryStyle, let subStyle, let keystone, secondary.count == 2 else {
            return nil
        }
        let primary = primaryPerks.compactMap(\.self)
        let shards = shards.compactMap(\.self)
        guard primary.count == 3, shards.count == 3 else { return nil }
        return RunePage(
            primaryStyle: primaryStyle, subStyle: subStyle,
            perks: [keystone] + primary + secondary.map(\.perk) + shards)
    }

    private static func perk(_ perk: PerkID?, ifIn rows: [[PerkID]], at index: Int) -> PerkID? {
        guard let perk, rows.indices.contains(index), rows[index].contains(perk) else {
            return nil
        }
        return perk
    }
}

extension PerkStyle {
    /// The perks of each row of `kind`, in client order.
    func rows(_ kind: Slot.Kind) -> [[PerkID]] {
        slots.filter { $0.kind == kind }.map(\.perks)
    }
}
