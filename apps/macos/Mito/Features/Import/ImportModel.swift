import AppKit
import Foundation
import LCUKit
import MitoAssets
import MitoCore
import MitoEngine
import MitoImport
import Observation

/// Imports the local player's loadout, adapted to the lane opponent and the enemy team, from the
/// open snapshot once per champion and champ select (§13.1), with the champion's override applied
/// (§21.5), and reports it as a toast in the main window or, when the window is not in front, a
/// notification. Each part goes to the `import_log` (§17).
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
    private let store: any PersonalStore
    private let detectedFlash: @MainActor () -> ImportSettings.FlashPosition?

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
        store: any PersonalStore = UnavailablePersonalStore(),
        /// The slot detected from the history, `.d` or `.f`, for `flashPosition == .auto`.
        detectedFlash: @escaping @MainActor () -> ImportSettings.FlashPosition? = { nil },
        poster: any NotificationPosting = SystemNotificationPoster(),
        appIsActive: @escaping @MainActor () -> Bool = { NSApplication.shared.isActive }
    ) {
        self.connection = connection
        readStats = stats
        self.store = store
        self.detectedFlash = detectedFlash
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
        var updated = outcome
        updated.report.runes = report.runes
        await log(updated, parts: [.runes])
        guard generation == self.generation else { return }
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
        var settings = settings()
        guard let target = Self.target(in: session, onHover: settings.importOnHover),
            imported.insert(target.champion).inserted
        else { return }
        let generation = generation
        let stats = readStats()
        guard stats.meta != nil else {
            await tellMissingStats(for: (target.champion, target.role))
            return
        }
        // Blind pick: the champion's most played role, or nothing without data.
        guard let role = target.role ?? Self.mostPlayedRole(of: target.champion, in: stats)
        else { return }
        let opponent = Self.laneOpponent(among: target.draft.enemies, in: role, stats: stats)
        let general = LoadoutSelection.general(for: target.champion, role: role, stats: stats)
        let adapted = LoadoutSelection.adapted(
            for: target.champion, role: role, opponent: opponent,
            enemyProfile: Composition.enemyProfile(in: target.draft, stats: stats),
            enemies: target.draft.enemies.compactMap(\.champion), stats: stats)
        let override = await championOverride(target.champion, role)
        guard generation == self.generation else { return }
        if settings.flashPosition == .auto, let detected = detectedFlash() {
            settings.flashPosition = detected
        }
        let plan = Self.plan(
            general: Self.withBlockTitles(general.loadout),
            adapted: Self.withBlockTitles(adapted.loadout), override: override, settings: settings)
        let loadout = plan.loadout
        guard loadout.runes != nil || loadout.spells != nil || loadout.itemSet != nil else {
            return
        }
        let lowSample = ImportOutcome.Part.allCases.filter { part in
            plan.origins[part] != .override
                && (plan.general.contains(part) ? general : adapted).sampleLevels[part]?
                    .isLowSample == true
        }
        await importLoadout(
            plan, lowSample: Set(lowSample), reasons: adapted.loadout.explanation,
            for: (target.champion, role, opponent), session: session, settings: settings)
    }

    /// At least even odds, so a coin-toss guess never picks the matchup (§12.3).
    static let minimumLaneOdds = 0.5

    /// The enemy assigned to `role` or, among the locked enemies without a role, the likeliest one
    /// in it, from `minimumLaneOdds` up (§12.3).
    static func laneOpponent(
        among enemies: [DraftSlot], in role: Role, stats: some StatsProvider
    ) -> ChampionID? {
        if let assigned = enemies.first(where: { $0.role == role && $0.champion != nil }) {
            return assigned.champion
        }
        let inferred = RoleInference.infer(
            enemies: enemies.filter { $0.role == nil }.compactMap(\.champion),
            takenRoles: Set(enemies.compactMap(\.role)), stats: stats)
        guard
            let likeliest = inferred.max(by: {
                $0.roleProbabilities[role, default: 0] < $1.roleProbabilities[role, default: 0]
            }), likeliest.roleProbabilities[role, default: 0] >= minimumLaneOdds
        else { return nil }
        return likeliest.champion
    }

    /// An unreadable store reads as no override: the general loadout still goes.
    private func championOverride(_ champion: ChampionID, _ role: Role) async -> ChampionOverride? {
        let overrides = try? await store.overrides()
        return overrides?.first { $0.champion == champion && $0.role == role }
    }

    struct Plan: Equatable {
        var loadout: Loadout
        var origins: [ImportOutcome.Part: ImportOutcome.Origin] = [:]
        /// Parts sent from the general loadout instead of the adapted one.
        var general: Set<ImportOutcome.Part> = []
        /// The override's "no importar": no item set is sent, and the old Mito set stays.
        var skipsItems = false
    }

    /// The override's choices over the adapted loadout (§13.1). The rune mode "general" sends the
    /// general page, and a fixed mode with nothing saved sends the general part, as its marker
    /// says. A part switched off in Settings is left alone: the importer skips it whatever the
    /// override says.
    static func plan(
        general: Loadout, adapted: Loadout, override: ChampionOverride?, settings: ImportSettings
    ) -> Plan {
        var runes = adapted.runes
        var spells = adapted.spells
        var itemSet = adapted.itemSet
        var plan = Plan(loadout: adapted)

        func useGeneral(_ part: ImportOutcome.Part, saying origin: ImportOutcome.Origin? = nil) {
            plan.general.insert(part)
            plan.origins[part] = origin
            switch part {
            case .runes: runes = general.runes
            case .spells: spells = general.spells
            case .items: itemSet = general.itemSet
            }
        }

        if settings.importRunes {
            // `.adaptive` is the editor's default, "sin preferencia": the global mode decides.
            let mode: ImportSettings.RuneMode =
                switch override?.runeMode {
                case .fixed?: .fixedPerChampion
                case .general?: .general
                case .adaptive?, .unknown?, nil: settings.runeMode
                }
            switch mode {
            case .fixedPerChampion:
                if let page = override?.fixedPage {
                    runes = page
                    plan.origins[.runes] = .override
                } else {
                    useGeneral(.runes, saying: .noFixedChoice)
                }
            case .general: useGeneral(.runes)
            case .adaptive: break
            }
        }

        if settings.importSpells, override?.spellMode == .fixed {
            if let pair = override?.fixedSpells {
                spells = pair
                plan.origins[.spells] = .override
            } else {
                useGeneral(.spells, saying: .noFixedChoice)
            }
        }

        if settings.importItemSets, let override {
            switch override.itemMode {
            case .fixedSet:
                if let set = override.fixedItems {
                    itemSet = set
                    plan.origins[.items] = .override
                } else {
                    useGeneral(.items, saying: .noFixedChoice)
                }
            case .skip:
                itemSet = nil
                plan.skipsItems = true
                plan.origins[.items] = .override
            case .recommended, .unknown:
                break
            }
        }

        plan.loadout = Loadout(
            runes: runes, spells: spells, itemSet: itemSet, skillOrder: adapted.skillOrder)
        return plan
    }

    /// Ties go to the earlier role in `Role.allCases`.
    static func mostPlayedRole(of champion: ChampionID, in stats: some StatsProvider) -> Role? {
        let games = stats.roleGames(for: champion)
        return Role.allCases.filter { games[$0, default: 0] > 0 }
            .max { games[$0, default: 0] < games[$1, default: 0] }
    }

    /// The §12.2 mapping decides what is locked; the hover counts only with `importOnHover`.
    static func target(in session: ChampSelectSession, onHover: Bool) -> (
        champion: ChampionID, role: Role?, draft: DraftContext
    )? {
        guard
            let draft = session.draftContext(
                queue: .other(QueueID(rawValue: 0)), patch: Patch(rawValue: ""), pickable: []),
            let me = draft.allies.first(where: { $0.cellId == draft.myCellId })
        else { return nil }
        if let locked = me.champion { return (locked, draft.myRole, draft) }
        if onHover, let hover = me.hover { return (hover, draft.myRole, draft) }
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
        Self.name(of: champion, in: try? await catalog.load())
    }

    private static func name(of champion: ChampionID, in data: GameData?) -> String {
        data?.champion(champion)?.name ?? String(champion.rawValue)
    }

    private static func name(of item: ItemID, in data: GameData?) -> String {
        data?.item(item)?.name ?? String(item.rawValue)
    }

    private func importLoadout(
        _ plan: Plan, lowSample: Set<ImportOutcome.Part>, reasons: [Reason],
        for target: (champion: ChampionID, role: Role, opponent: ChampionID?),
        session: ChampSelectSession, settings: ImportSettings
    ) async {
        let loadout = plan.loadout
        let generation = generation
        async let gameflow = try? connection.send(.gameflowSession)
        async let summoner = try? connection.send(.currentSummoner)
        async let gameData = try? catalog.load()
        let (mapID, summonerId) = await (gameflow?.mapID, summoner?.summonerId)
        let data = await gameData

        let map: ItemSetMap? = mapID == ItemSetMap.summonersRift.id ? .summonersRift : nil
        let itemsUnavailable: ImportOutcome.ItemsUnavailable? =
            if plan.skipsItems {
                .skippedByOverride
            } else if loadout.itemSet == nil || !settings.importItemSets {
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
            title: Self.title(Self.name(of: target.champion, in: data), target.role),
            champion: target.champion,
            map: map ?? .summonersRift, session: session,
            // Unused without an item set, which is all a missing ID allows.
            summonerId: summonerId ?? 0)

        let report = await importer.apply(sent, settings: settings, context: context)
        let outcome = ImportOutcome(
            id: nextID(), champion: target.champion, opponent: target.opponent,
            title: context.title, report: report, itemsUnavailable: itemsUnavailable,
            lowSample: lowSample, origins: plan.origins,
            adaptations: Self.adaptations(reasons, in: data).filter {
                plan.origins[$0.key] == nil && !plan.general.contains($0.key)
            })
        await log(outcome, parts: ImportOutcome.Part.allCases)
        guard generation == self.generation else { return }
        await present(outcome, runes: sent.runes.map { ($0, context) })
    }

    /// The toast's markers for each part, in reason order and without repeats.
    private static func adaptations(_ reasons: [Reason], in data: GameData?)
        -> [ImportOutcome.Part: [ImportOutcome.Adaptation]]
    {
        var byPart: [ImportOutcome.Part: [ImportOutcome.Adaptation]] = [:]
        for reason in reasons {
            let entry: (ImportOutcome.Part, ImportOutcome.Adaptation)? =
                switch reason.kind {
                case .adaptedToOpponent(let part, let opponent, _):
                    ImportOutcome.Part(part).map { ($0, .opponent(name(of: opponent, in: data))) }
                case .adaptedToProfile(let part, let profile, _):
                    ImportOutcome.Part(part).map { ($0, .profile(profile)) }
                case .countersFlag(let item, let flag, let enemies):
                    (
                        .items,
                        .countersFlag(item: name(of: item, in: data), flag: flag, enemies: enemies)
                    )
                case .situationalItem(let item, let profile, _, _, _):
                    (.items, .situational(item: name(of: item, in: data), profile: profile))
                default: nil
                }
            guard let (part, adaptation) = entry, byPart[part]?.contains(adaptation) != true
            else { continue }
            byPart[part, default: []].append(adaptation)
        }
        return byPart
    }

    /// The client already holds what was sent, so a log write that fails changes nothing else.
    private func log(_ outcome: ImportOutcome, parts: [ImportOutcome.Part]) async {
        for entry in outcome.logEntries(parts, at: .now) {
            try? await store.appendImportLog(entry)
        }
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
            .loadoutImported(champion: outcome.champion, opponent: outcome.opponent),
            title: outcome.headline)
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

    /// The engine titles each block with its `BuildLayer` raw value or
    /// `situationalBlockTitle`; the client shows the title.
    private static func withBlockTitles(_ loadout: Loadout) -> Loadout {
        Loadout(
            runes: loadout.runes, spells: loadout.spells,
            itemSet: loadout.itemSet.map { set in
                ItemSet(
                    blocks: set.blocks.map { block in
                        ItemSet.Block(title: blockTitle(block.title), items: block.items)
                    })
            },
            skillOrder: loadout.skillOrder)
    }

    private static func blockTitle(_ engineTitle: String) -> String {
        if engineTitle == LoadoutSelection.situationalBlockTitle {
            return String(localized: "Situacionales", table: "Import")
        }
        return BuildLayer(rawValue: engineTitle)?.blockTitle ?? engineTitle
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
            id: id, champion: champion, opponent: opponent, title: title, report: report,
            itemsUnavailable: itemsUnavailable, lowSample: lowSample, origins: origins,
            adaptations: adaptations, isMissingStats: isMissingStats)
    }
}

extension ImportOutcome.Part {
    /// The skill order is not imported.
    fileprivate init?(_ part: LoadoutPart) {
        switch part {
        case .runes: self = .runes
        case .spells: self = .spells
        case .items: self = .items
        case .skillOrder: return nil
        }
    }
}

extension LoadoutSampleLevels {
    fileprivate subscript(part: ImportOutcome.Part) -> SampleLevel? {
        switch part {
        case .runes: runes
        case .spells: spells
        case .items: itemSet
        }
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
