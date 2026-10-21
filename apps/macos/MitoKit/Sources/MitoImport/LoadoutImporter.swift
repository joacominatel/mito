public import LCUKit
public import MitoCore

/// What the three importers need besides the loadout and the settings.
public struct LoadoutImportContext: Sendable {
    /// Shown after `Mito · ` on the rune page and the item set, e.g. `"Ahri MID vs Zed"`.
    public let title: String
    public let champion: ChampionID
    public let map: ItemSetMap
    /// The current champ select session, for the spells' Flash slot and already-selected check.
    public let session: ChampSelectSession
    /// From `CurrentSummoner`.
    public let summonerId: Int
    /// The `pageID` of a runes `.needsConfirmation` the user accepted.
    public let confirmedReplacement: Int?

    public init(
        title: String, champion: ChampionID, map: ItemSetMap = .summonersRift,
        session: ChampSelectSession, summonerId: Int, confirmedReplacement: Int? = nil
    ) {
        self.title = title
        self.champion = champion
        self.map = map
        self.session = session
        self.summonerId = summonerId
        self.confirmedReplacement = confirmedReplacement
    }
}

public enum StepResult: Equatable, Sendable {
    case applied
    /// Nothing was sent.
    case skipped(StepSkipReason)
    case failed(StepError)
    /// Nothing was sent. Apply again with `confirmedReplacement: pageID` once the user accepts
    /// overwriting the page.
    case needsConfirmation(pageID: Int, pageName: String)
}

public enum StepSkipReason: Equatable, Sendable {
    /// The loadout has no recommendation for this part.
    case notInLoadout
    /// The part's toggle in `ImportSettings` is off.
    case disabled
    /// The spells are already the current selection.
    case alreadySelected
    /// The rune target is missing or locked, or the current page is not editable.
    case noEditablePage
}

public enum StepError: Equatable, Sendable {
    case lcu(LCUError)
    /// The page was not sent: the client would reject it or leave the player without runes.
    case invalidRunePage(RunePageValidationError)
}

/// One result per imported part. Skill order is not imported: the client has no API for it.
public struct ImportReport: Equatable, Sendable {
    public var runes: StepResult
    public var spells: StepResult
    public var items: StepResult

    public init(runes: StepResult, spells: StepResult, items: StepResult) {
        self.runes = runes
        self.spells = spells
        self.items = items
    }
}

/// Applies a whole loadout through the rune, spell, and item set importers (`MITO_CONTEXT.md`
/// §13.5). Steps run in that order and independently; overlapping applies run one after another.
public actor LoadoutImporter {
    private let runes: RuneImporter
    private let spells: SpellImporter
    private let items: ItemSetImporter
    private var last: Task<ImportReport, Never>?

    public init(connection: any LCUConnection) {
        runes = RuneImporter(connection: connection)
        spells = SpellImporter(connection: connection)
        items = ItemSetImporter(connection: connection)
    }

    public func apply(
        _ loadout: Loadout, settings: ImportSettings, context: LoadoutImportContext
    ) async -> ImportReport {
        // The actor is reentrant at every LCU call, so chaining is what keeps applies apart.
        let previous = last
        let task = Task {
            _ = await previous?.value
            return await run(loadout, settings, context)
        }
        last = task
        return await task.value
    }

    private func run(
        _ loadout: Loadout, _ settings: ImportSettings, _ context: LoadoutImportContext
    ) async -> ImportReport {
        var report = ImportReport(
            runes: .skipped(.notInLoadout), spells: .skipped(.notInLoadout),
            items: .skipped(.notInLoadout))
        if let page = loadout.runes {
            report.runes = Self.step(
                await runes.apply(
                    page, title: context.title, settings: settings,
                    confirmedReplacement: context.confirmedReplacement))
        }
        if let pair = loadout.spells {
            report.spells = Self.step(
                await spells.apply(pair, settings: settings, session: context.session))
        }
        if let itemSet = loadout.itemSet {
            report.items = Self.step(
                await items.apply(
                    itemSet, champion: context.champion, map: context.map, title: context.title,
                    summonerId: context.summonerId, settings: settings))
        }
        return report
    }

    private static func step(_ result: RuneImportResult) -> StepResult {
        switch result {
        case .created, .updated, .replacedCurrentPage: .applied
        case .needsConfirmation(let pageID, let pageName):
            .needsConfirmation(pageID: pageID, pageName: pageName)
        case .noEditablePage: .skipped(.noEditablePage)
        case .invalid(let error): .failed(.invalidRunePage(error))
        case .disabled: .skipped(.disabled)
        case .failed(let error): .failed(.lcu(error))
        }
    }

    private static func step(_ result: SpellImportResult) -> StepResult {
        switch result {
        case .applied: .applied
        case .skipped(.disabled): .skipped(.disabled)
        case .skipped(.alreadySelected): .skipped(.alreadySelected)
        case .failed(let error): .failed(.lcu(error))
        }
    }

    private static func step(_ result: ItemSetImportResult) -> StepResult {
        switch result {
        case .applied: .applied
        case .disabled: .skipped(.disabled)
        case .failed(let error): .failed(.lcu(error))
        }
    }
}
