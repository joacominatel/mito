public import MitoCore

/// Why a page was not sent; the client would reject it or leave the player without runes.
public enum RunePageValidationError: Equatable, Sendable {
    /// A page holds exactly 9 perks.
    case wrongPerkCount(Int)
    case sameStyleTwice
    /// The client's `/lol-perks/v1/styles` has no such style.
    case unknownStyle(PerkStyleID)
    /// The client's style lacks a keystone row, three regular rows, or three shard rows.
    case unexpectedStyleLayout(PerkStyleID)
    /// `perks[index]` is not in the row that position takes it from.
    case perkOutOfPlace(index: Int, perk: PerkID)
    /// The two secondary perks cannot come from two different rows.
    case secondaryPerksShareARow
}

extension RunePage {
    /// Checks the page against the client's styles, row by row: a shard ID can sit in more than
    /// one shard row (`MITO_CONTEXT.md` §16.2), so a perk is never mapped back to "its" row.
    func validationError(against styles: [PerkStyle]) -> RunePageValidationError? {
        guard perks.count == 9 else { return .wrongPerkCount(perks.count) }
        guard primaryStyle != subStyle else { return .sameStyleTwice }
        guard let primary = styles.first(where: { $0.id == primaryStyle }) else {
            return .unknownStyle(primaryStyle)
        }
        guard let secondary = styles.first(where: { $0.id == subStyle }) else {
            return .unknownStyle(subStyle)
        }
        let keystones = primary.rows(.keystone)
        let regular = primary.rows(.regular)
        let shards = primary.rows(.statMod)
        guard keystones.count == 1, regular.count == 3, shards.count == 3 else {
            return .unexpectedStyleLayout(primary.id)
        }
        let secondaryRows = secondary.rows(.regular)
        guard secondaryRows.count >= 2 else { return .unexpectedStyleLayout(secondary.id) }

        for (index, row) in zip([0, 1, 2, 3, 6, 7, 8], keystones + regular + shards)
        where !row.contains(perks[index]) {
            return .perkOutOfPlace(index: index, perk: perks[index])
        }
        for index in 4...5 where !secondaryRows.contains(where: { $0.contains(perks[index]) }) {
            return .perkOutOfPlace(index: index, perk: perks[index])
        }
        let inDifferentRows = secondaryRows.indices.contains { first in
            secondaryRows[first].contains(perks[4])
                && secondaryRows.indices.contains {
                    $0 != first && secondaryRows[$0].contains(perks[5])
                }
        }
        return inDifferentRows ? nil : .secondaryPerksShareARow
    }
}

extension PerkStyle {
    fileprivate func rows(_ kind: Slot.Kind) -> [[PerkID]] {
        slots.filter { $0.kind == kind }.map(\.perks)
    }
}
