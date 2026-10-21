import AppKit
import Foundation
import LCUKit
import MitoAssets
import MitoCore
import MitoEngine
import MitoImport
import Observation

/// Imports the local player's general loadout from the open snapshot once per champion and champ
/// select (§13.1) and reports it as a toast in the main window or, when the window is not in
/// front, a notification.
@Observable
final class ImportModel {
    /// The latest import while the window shows it, and any import waiting on a rune confirmation.
    private(set) var outcome: ImportOutcome?
    /// Editable rune pages, for picking the reserved page in Settings.
    private(set) var editablePages: [PerkPage] = []

    let settings: @MainActor () -> ImportSettings
    private let connection: any LCUConnection
    private let importer: LoadoutImporter
    private let catalog: GameDataCatalog
    private let poster: any NotificationPosting
    private let appIsActive: @MainActor () -> Bool
    private let readStats: @MainActor () -> any StatsProvider

    @ObservationIgnored private var imported: Set<ChampionID> = []
    @ObservationIgnored private var toldMissingStats = false
    @ObservationIgnored private var pendingRunes: (page: RunePage, context: LoadoutImportContext)?
    @ObservationIgnored private var windows = 0
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var lastID = 0

    init(
        connection: any LCUConnection,
        catalog: GameDataCatalog,
        settings: @escaping @MainActor () -> ImportSettings = { ImportSettings() },
        stats: @escaping @MainActor () -> any StatsProvider = { NoStats() },
        poster: any NotificationPosting = SystemNotificationPoster(),
        appIsActive: @escaping @MainActor () -> Bool = { NSApplication.shared.isActive }
    ) {
        self.connection = connection
        readStats = stats
        self.catalog = catalog
        self.settings = settings
        self.poster = poster
        self.appIsActive = appIsActive
        importer = LoadoutImporter(connection: connection)
    }

    /// Returns once the connection's streams finish and every session event is handled.
    func run() async {
        await withDiscardingTaskGroup { group in
            group.addTask { await self.followSession() }
            for await state in connection.states() where state != .connected {
                reset()
            }
        }
    }

    // MARK: Window

    /// The main window's toast host calls these as it appears and disappears.
    func windowAppeared() { windows += 1 }
    func windowDisappeared() { windows = max(windows - 1, 0) }

    private var isWindowInFront: Bool { windows > 0 && appIsActive() }

    // MARK: User actions

    /// Re-applies only the runes, overwriting the page the user agreed to replace.
    func confirmReplacement() async {
        guard let outcome, case .needsConfirmation(let pageID, _) = outcome.status,
            let pendingRunes
        else { return }
        self.pendingRunes = nil
        let generation = generation
        let context = pendingRunes.context
        let confirmed = LoadoutImportContext(
            title: context.title, champion: context.champion, map: context.map,
            session: context.session, summonerId: context.summonerId,
            confirmedReplacement: pageID)
        let report = await importer.apply(
            Loadout(runes: pendingRunes.page, spells: nil, itemSet: nil, skillOrder: nil),
            settings: settings(), context: confirmed)
        guard generation == self.generation else { return }
        var updated = outcome
        updated.report.runes = report.runes
        await present(updated.renumbered(nextID()), runes: (pendingRunes.page, context))
    }

    func declineReplacement() {
        pendingRunes = nil
        outcome = nil
    }

    /// The toast's timeout; an outcome waiting on a confirmation stays.
    func dismiss(_ id: ImportOutcome.ID) {
        guard outcome?.id == id, outcome?.needsConfirmation == false else { return }
        outcome = nil
    }

    func loadEditablePages() async {
        guard let pages = try? await connection.send(.perkPages) else { return }
        editablePages = pages.filter { $0.isEditable == true }
    }

    // MARK: Trigger

    private func followSession() async {
        for await event in connection.events([.champSelectSession]) {
            if event.eventType == .delete {
                reset()
                continue
            }
            guard let session = try? ChampSelectSession(event) else { continue }
            await handle(session)
        }
    }

    private func handle(_ session: ChampSelectSession) async {
        let settings = settings()
        guard let target = Self.target(in: session, onHover: settings.importOnHover),
            imported.insert(target.champion).inserted
        else { return }
        let stats = readStats()
        guard stats.meta != nil else {
            await tellMissingStats(for: target)
            return
        }
        // Blind pick: the champion's most played role, or nothing without data.
        guard let role = target.role ?? Self.mostPlayedRole(of: target.champion, in: stats)
        else { return }
        let general = LoadoutSelection.general(for: target.champion, role: role, stats: stats)
        let loadout = Self.withBlockTitles(general.loadout)
        guard loadout.runes != nil || loadout.spells != nil || loadout.itemSet != nil else {
            return
        }
        await importLoadout(
            loadout, lowSample: Self.lowSampleParts(general.sampleLevels),
            for: (target.champion, role), session: session, settings: settings)
    }

    /// Ties go to the earlier role in `Role.allCases`.
    static func mostPlayedRole(of champion: ChampionID, in stats: some StatsProvider) -> Role? {
        let games = stats.roleGames(for: champion)
        return Role.allCases.filter { games[$0, default: 0] > 0 }
            .max { games[$0, default: 0] < games[$1, default: 0] }
    }

    /// The §12.2 mapping decides what is locked; the hover counts only with `importOnHover`.
    static func target(in session: ChampSelectSession, onHover: Bool) -> (
        champion: ChampionID, role: Role?
    )? {
        guard
            let draft = session.draftContext(
                queue: .other(QueueID(rawValue: 0)), patch: Patch(rawValue: ""), pickable: []),
            let me = draft.allies.first(where: { $0.cellId == draft.myCellId })
        else { return nil }
        if let locked = me.champion { return (locked, draft.myRole) }
        if onHover, let hover = me.hover { return (hover, draft.myRole) }
        return nil
    }

    /// Once per champ select: every champion would say the same thing.
    private func tellMissingStats(for target: (champion: ChampionID, role: Role?)) async {
        guard !toldMissingStats else { return }
        toldMissingStats = true
        let generation = generation
        let name = await championName(target.champion)
        guard generation == self.generation else { return }
        let outcome = ImportOutcome(
            id: nextID(), champion: target.champion, title: Self.title(name, target.role),
            report: ImportReport(
                runes: .skipped(.notInLoadout), spells: .skipped(.notInLoadout),
                items: .skipped(.notInLoadout)),
            itemsUnavailable: nil, isMissingStats: true)
        await present(outcome, runes: nil)
    }

    private func championName(_ champion: ChampionID) async -> String {
        let data = try? await catalog.load()
        return data?.champion(champion)?.name ?? String(champion.rawValue)
    }

    private func importLoadout(
        _ loadout: Loadout, lowSample: Set<ImportOutcome.Part>,
        for target: (champion: ChampionID, role: Role), session: ChampSelectSession,
        settings: ImportSettings
    ) async {
        let generation = generation
        async let gameflow = try? connection.send(.gameflowSession)
        async let summoner = try? connection.send(.currentSummoner)
        async let name = championName(target.champion)
        let (mapID, summonerId) = await (gameflow?.mapID, summoner?.summonerId)

        let map: ItemSetMap? = mapID == ItemSetMap.summonersRift.id ? .summonersRift : nil
        let itemsUnavailable: ImportOutcome.ItemsUnavailable? =
            if loadout.itemSet == nil || !settings.importItemSets {
                nil
            } else if map == nil {
                .unsupportedMap
            } else if summonerId == nil {
                .noAccount
            } else {
                nil
            }
        let sent =
            itemsUnavailable == nil
            ? loadout
            : Loadout(
                runes: loadout.runes, spells: loadout.spells, itemSet: nil,
                skillOrder: loadout.skillOrder)
        let context = LoadoutImportContext(
            title: Self.title(await name, target.role), champion: target.champion,
            map: map ?? .summonersRift, session: session,
            // Unused without an item set, which is all a missing ID allows.
            summonerId: summonerId ?? 0)

        let report = await importer.apply(sent, settings: settings, context: context)
        guard generation == self.generation else { return }
        let outcome = ImportOutcome(
            id: nextID(), champion: target.champion, title: context.title, report: report,
            itemsUnavailable: itemsUnavailable, lowSample: lowSample)
        await present(outcome, runes: sent.runes.map { ($0, context) })
    }

    // MARK: Feedback

    private func present(
        _ outcome: ImportOutcome, runes: (page: RunePage, context: LoadoutImportContext)?
    ) async {
        let needsConfirmation = outcome.needsConfirmation
        pendingRunes = needsConfirmation ? runes : nil
        if outcome.status == .unchanged {
            self.outcome = nil
            return
        }
        if isWindowInFront {
            self.outcome = outcome
            return
        }
        // Kept for the window and the menu: the confirmation is never answered for the user.
        self.outcome = needsConfirmation ? outcome : nil
        await poster.post(
            .loadoutImported(champion: outcome.champion, opponent: nil), title: outcome.headline)
    }

    private func reset() {
        generation += 1
        imported = []
        toldMissingStats = false
        pendingRunes = nil
        outcome = nil
    }

    private func nextID() -> Int {
        lastID += 1
        return lastID
    }

    private static func title(_ name: String, _ role: Role?) -> String {
        guard let role else { return name }
        let short =
            switch role {
            case .top: String(localized: "TOP", table: "Import")
            case .jungle: String(localized: "JGL", table: "Import")
            case .middle: String(localized: "MID", table: "Import")
            case .bottom: String(localized: "ADC", table: "Import")
            case .utility: String(localized: "SUP", table: "Import")
            }
        return "\(name) \(short)"
    }

    /// The engine titles each block with its `BuildLayer` raw value; the client shows the title.
    private static func withBlockTitles(_ loadout: Loadout) -> Loadout {
        Loadout(
            runes: loadout.runes, spells: loadout.spells,
            itemSet: loadout.itemSet.map { set in
                ItemSet(
                    blocks: set.blocks.map { block in
                        ItemSet.Block(
                            title: BuildLayer(rawValue: block.title)?.blockTitle ?? block.title,
                            items: block.items)
                    })
            },
            skillOrder: loadout.skillOrder)
    }

    private static func lowSampleParts(_ levels: LoadoutSampleLevels) -> Set<ImportOutcome.Part> {
        let parts: [(ImportOutcome.Part, SampleLevel?)] = [
            (.runes, levels.runes), (.spells, levels.spells), (.items, levels.itemSet),
        ]
        return Set(parts.filter { $0.1?.isLowSample == true }.map(\.0))
    }

    private struct NoStats: StatsProvider {
        func roleGames(for champion: ChampionID) -> [Role: Int] { [:] }
    }
}

extension BuildLayer {
    /// The item set block heading in the client (§13.4).
    fileprivate var blockTitle: String {
        switch self {
        case .start: String(localized: "Inicio", table: "Import")
        case .core: String(localized: "Núcleo", table: "Import")
        case .boots: String(localized: "Botas", table: "Import")
        case .fourth: String(localized: "4.º ítem", table: "Import")
        case .fifth: String(localized: "5.º ítem", table: "Import")
        case .sixth: String(localized: "6.º ítem", table: "Import")
        }
    }
}

extension ImportOutcome {
    fileprivate func renumbered(_ id: Int) -> ImportOutcome {
        ImportOutcome(
            id: id, champion: champion, title: title, report: report,
            itemsUnavailable: itemsUnavailable, lowSample: lowSample,
            isMissingStats: isMissingStats)
    }
}

extension GameSettings {
    /// The menu's auto-accept check: on for any mode but `off`; checking it again picks `always`.
    var isAutoAcceptOn: Bool {
        get { autoAccept != .off }
        set {
            if !newValue {
                autoAccept = .off
            } else if autoAccept == .off {
                autoAccept = .always
            }
        }
    }
}
