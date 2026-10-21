public import LCUKit
public import MitoCore

public enum SpellImportResult: Equatable, Sendable {
    /// The pair as sent, after the Flash position rule.
    case applied(SpellPair)
    case skipped(SpellImportSkipReason)
    case failed(LCUError)
}

public enum SpellImportSkipReason: Equatable, Sendable {
    /// `ImportSettings.importSpells` is off.
    case disabled
    case alreadySelected
}

/// Sets the local player's summoner spells in champ select (`MITO_CONTEXT.md` §13.3).
public struct SpellImporter: Sendable {
    // §13.3's ID, unverified until the static data units read it from summoner.json.
    static let flash = SummonerSpellID(rawValue: 4)

    private let connection: any LCUConnection

    public init(connection: any LCUConnection) {
        self.connection = connection
    }

    /// `session` supplies the local player's current spells: the `auto` Flash slot and the
    /// already-selected check.
    public func apply(
        _ recommended: SpellPair, settings: ImportSettings, session: ChampSelectSession
    ) async -> SpellImportResult {
        guard settings.importSpells else { return .skipped(.disabled) }
        let current = session.myTeam.first {
            $0.cellId != nil && $0.cellId == session.localPlayerCellId
        }
        let pair = Self.arrange(
            recommended, flashPosition: settings.flashPosition,
            currentFlashInD: current.flatMap(Self.flashInD))
        if let current, current.spell1Id == pair.first, current.spell2Id == pair.second {
            return .skipped(.alreadySelected)
        }
        do {
            _ = try await connection.send(.updateMySelection(spells: pair))
            return .applied(pair)
        } catch {
            return .failed(error)
        }
    }

    private static func flashInD(_ member: ChampSelectSession.Member) -> Bool? {
        if member.spell1Id == flash { return true }
        if member.spell2Id == flash { return false }
        return nil
    }

    private static func arrange(
        _ pair: SpellPair, flashPosition: ImportSettings.FlashPosition, currentFlashInD: Bool?
    ) -> SpellPair {
        let other: SummonerSpellID
        if pair.first == flash {
            other = pair.second
        } else if pair.second == flash {
            other = pair.first
        } else {
            return pair
        }
        let flashInD =
            switch flashPosition {
            case .d: true
            case .f: false
            case .auto: currentFlashInD ?? (pair.first == flash)
            }
        return flashInD
            ? SpellPair(first: flash, second: other) : SpellPair(first: other, second: flash)
    }
}
