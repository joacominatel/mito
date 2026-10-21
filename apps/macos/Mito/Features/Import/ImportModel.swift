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
/// (§21.5), and re-sends what a later lane opponent or enemy profile changes. Reports it as a
/// toast in the main window or, when the window is not in front, a notification. Each part goes
/// to the `import_log` (§17).
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
    private let scoringRole: @MainActor () -> Role?

    @ObservationIgnored private var imported: Set<ChampionID> = []
    @ObservationIgnored private var lastImports: [ChampionID: LastImport] = [:]
    @ObservationIgnored private var toldNothingToImport = false
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
        /// The champ-select selector's role (§20.3), which blind pick imports for.
        scoringRole: @escaping @MainActor () -> Role? = { nil },
        poster: any NotificationPosting = SystemNotificationPoster(),
        appIsActive: @escaping @MainActor () -> Bool = { NSApplication.shared.isActive }
    ) {
        self.connection = connection
        readStats = stats
        self.store = store
        self.detectedFlash = detectedFlash
        self.scoringRole = scoringRole
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
        if report.runes == .applied { lastImports[context.champion]?.runes = pendingRunes.page }
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
        guard let target = Self.target(in: session, onHover: settings.importOnHover) else {
            return
        }
        guard imported.insert(target.champion).inserted else {
            await reimportIfNeeded(target, session: session)
            return
        }
        let generation = generation
        // Only blind pick needs the queue: ARAM has no assigned roles.
        let queue =
            target.role == nil
            ? (try? await connection.send(.gameflowSession))?.queueType : nil
        guard generation == self.generation else { return }
        let isARAM = queue == .aram
        let stats = readStats()
        guard isARAM || stats.meta != nil else {
            await tellNothingToImport(.stats, for: (target.champion, target.role))
            return
        }
        guard
            let prepared = await prepare(
                target.champion, queue: queue ?? target.draft.queue,
                role: target.role ?? scoringRole(), in: target.draft, stats: stats,
                settings: settings),
            generation == self.generation
        else { return }
        guard !prepared.plan.isEmpty else {
            if isARAM { await tellNothingToImport(.aramBuild, for: (target.champion, nil)) }
            return
        }
        await importLoadout(prepared, session: session)
    }

    /// What one import of a champion is built from, before anything reaches the client.
    private struct Prepared {
        let champion: ChampionID
        /// `nil` in ARAM.
        let role: Role?
        let opponent: ChampionID?
        let profile: Set<EnemyProfile>
        let plan: ImportPlan
        let lowSample: Set<ImportOutcome.Part>
        let reasons: [Reason]
        /// With `flashPosition` resolved.
        let settings: ImportSettings
    }

    /// `nil` without a role to import for (§13.1).
    private func prepare(
        _ champion: ChampionID, queue: QueueType, role: Role?, in draft: DraftContext,
        stats: any StatsProvider, settings: ImportSettings
    ) async -> Prepared? {
        let generation = generation
        // An unreadable store reads as no override: the general loadout still goes.
        let overrides = (try? await store.overrides()) ?? []
        guard generation == self.generation,
            let decided = ImportTarget.decide(
                for: champion, queue: queue, role: role, enemies: draft.enemies, stats: stats,
                overrides: overrides, settings: settings)
        else { return nil }
        var settings = settings
        if settings.flashPosition == .auto, let detected = detectedFlash() {
            settings.flashPosition = detected
        }
        var plan = decided.plan
        // The override's set keeps the user's block titles.
        if plan.origins[.items] != .override { plan.loadout = Self.withBlockTitles(plan.loadout) }
        let lowSample = ImportOutcome.Part.allCases.filter { part in
            plan.origins[part] != .override
                && (plan.general.contains(part) ? decided.general : decided.adapted)
                    .sampleLevels[part]?.isLowSample == true
        }
        return Prepared(
            champion: champion, role: decided.role, opponent: decided.opponent?.champion,
            profile: decided.enemyProfile, plan: plan, lowSample: Set(lowSample),
            reasons: decided.adapted.loadout.explanation, settings: settings)
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
    private func tellNothingToImport(
        _ missing: ImportOutcome.Missing, for target: (champion: ChampionID, role: Role?)
    ) async {
        guard !toldNothingToImport else { return }
        toldNothingToImport = true
        let generation = generation
        let name = await championName(target.champion)
        guard generation == self.generation else { return }
        let outcome = ImportOutcome(
            id: nextID(), champion: target.champion, title: Self.title(name, target.role),
            report: ImportReport(
                runes: .skipped(.notInLoadout), spells: .skipped(.notInLoadout),
                items: .skipped(.notInLoadout)),
            itemsUnavailable: nil, missing: missing)
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

    private func importLoadout(_ prepared: Prepared, session: ChampSelectSession) async {
        let plan = prepared.plan
        let settings = prepared.settings
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
            title: Self.title(Self.name(of: prepared.champion, in: data), prepared.role),
            champion: prepared.champion,
            map: map ?? .summonersRift, session: session,
            // Unused without an item set, which is all a missing ID allows.
            summonerId: summonerId ?? 0)

        let report = await importer.apply(sent, settings: settings, context: context)
        let outcome = ImportOutcome(
            id: nextID(), champion: prepared.champion, opponent: prepared.opponent,
            title: context.title, report: report, itemsUnavailable: itemsUnavailable,
            lowSample: prepared.lowSample, origins: plan.origins,
            adaptations: Self.adaptations(prepared.reasons, in: data).filter {
                plan.origins[$0.key] == nil && !plan.general.contains($0.key)
            })
        await log(outcome, parts: ImportOutcome.Part.allCases)
        guard generation == self.generation else { return }
        lastImports[prepared.champion] = LastImport(
            role: prepared.role, opponent: prepared.opponent, profile: prepared.profile,
            context: context,
            runes: report.runes == .applied ? sent.runes : nil,
            spells: report.spells.leftThePair ? sent.spells : nil,
            itemSet: report.items == .applied ? sent.itemSet : nil)
        await present(outcome, runes: sent.runes.map { ($0, context) })
    }

    // MARK: Re-import

    /// What an import left in the client, and the context it was adapted to (§13.1).
    private struct LastImport {
        /// `nil` in ARAM, whose fixed choices never change with the context.
        let role: Role?
        var opponent: ChampionID?
        var profile: Set<EnemyProfile>
        /// Its session is stale: a re-import sends the current one.
        let context: LoadoutImportContext
        /// What Mito put in the client, per part; `nil` once nothing of Mito's is there.
        var runes: RunePage?
        var spells: SpellPair?
        var itemSet: ItemSet?
    }

    /// Re-sends the parts whose recommendation changed with the lane opponent or the enemy
    /// profile, leaving alone what the user edited since and any pending rune confirmation.
    /// Overrides' fixed parts never change with the context, so they are never re-sent.
    private func reimportIfNeeded(
        _ target: (champion: ChampionID, role: Role?, draft: DraftContext),
        session: ChampSelectSession
    ) async {
        let current = settings()
        guard current.reimportOnOpponentChange, var last = lastImports[target.champion],
            let role = last.role,
            Self.target(in: session, onHover: false)?.champion == target.champion
        else { return }
        let generation = generation
        let stats = readStats()
        guard stats.meta != nil else { return }
        let opponent = ImportTarget.laneOpponent(
            among: target.draft.enemies, in: role, stats: stats)?.champion
        let profile = Composition.enemyProfile(in: target.draft, stats: stats)
        guard opponent != last.opponent || profile != last.profile else { return }
        let previousOpponent = last.opponent
        // Before any await, so the next session event does not start the same re-import.
        last.opponent = opponent
        last.profile = profile
        lastImports[target.champion] = last

        guard
            let prepared = await prepare(
                target.champion, queue: target.draft.queue, role: role, in: target.draft,
                stats: stats, settings: current),
            generation == self.generation
        else { return }
        let plan = prepared.plan
        let settings = prepared.settings
        func changed<Value: Equatable>(
            _ part: ImportOutcome.Part, _ isOn: Bool, sent: Value?, now: Value?
        ) -> Bool {
            guard isOn, plan.origins[part] == nil, !plan.general.contains(part),
                let sent, let now
            else { return false }
            return sent != now
        }
        let parts = ImportOutcome.Part.allCases.filter { part in
            switch part {
            case .runes:
                changed(part, settings.importRunes, sent: last.runes, now: plan.loadout.runes)
            case .spells:
                changed(part, settings.importSpells, sent: last.spells, now: plan.loadout.spells)
            case .items:
                changed(
                    part, settings.importItemSets, sent: last.itemSet, now: plan.loadout.itemSet)
            }
        }
        guard !parts.isEmpty else { return }

        var unread: [ImportOutcome.Part: StepResult] = [:]
        var manual: Set<ImportOutcome.Part> = []
        if settings.preserveManualChanges {
            for part in parts {
                switch await holdsWhatMitoSent(part, last, session: session) {
                case .success(true): break
                case .success(false): manual.insert(part)
                case .failure(let error): unread[part] = .failed(.lcu(error))
                }
            }
        }
        let resend = Set(parts).subtracting(manual).subtracting(unread.keys)
        let loadout = Loadout(
            runes: resend.contains(.runes) ? plan.loadout.runes : nil,
            spells: resend.contains(.spells) ? plan.loadout.spells : nil,
            itemSet: resend.contains(.items) ? plan.loadout.itemSet : nil, skillOrder: nil)
        let context = LoadoutImportContext(
            title: last.context.title, champion: target.champion, map: last.context.map,
            session: session, summonerId: last.context.summonerId)
        var report =
            resend.isEmpty
            ? ImportReport(
                runes: .skipped(.notInLoadout), spells: .skipped(.notInLoadout),
                items: .skipped(.notInLoadout))
            : await importer.apply(loadout, settings: settings, context: context)
        for (part, result) in unread { report[part] = result }
        let data = try? await catalog.load()

        let reason: ImportOutcome.Reimport.Reason =
            if let opponent, opponent != previousOpponent {
                .opponent(Self.name(of: opponent, in: data))
            } else {
                .enemyTeam
            }
        let outcome = ImportOutcome(
            id: nextID(), champion: target.champion, opponent: opponent, title: context.title,
            report: report, itemsUnavailable: nil,
            lowSample: prepared.lowSample.intersection(resend),
            adaptations: Self.adaptations(prepared.reasons, in: data).filter {
                resend.contains($0.key)
            },
            reimport: ImportOutcome.Reimport(reason: reason, parts: parts, manual: manual))
        await log(outcome, parts: parts)
        guard generation == self.generation, var held = lastImports[target.champion] else {
            return
        }
        // A part the user took over stays theirs for the rest of the champ select.
        if manual.contains(.runes) || report.runes.isNeedsConfirmation { held.runes = nil }
        if manual.contains(.spells) { held.spells = nil }
        if manual.contains(.items) { held.itemSet = nil }
        if report.runes == StepResult.applied { held.runes = loadout.runes }
        if report.spells.leftThePair { held.spells = loadout.spells }
        if report.items == StepResult.applied { held.itemSet = loadout.itemSet }
        lastImports[target.champion] = held
        // A pending confirmation keeps its toast: the re-import is told as a notification.
        guard pendingRunes == nil || outcome.needsConfirmation else {
            await poster.post(
                .loadoutImported(champion: outcome.champion, opponent: outcome.opponent),
                title: outcome.headline)
            return
        }
        await present(outcome, runes: loadout.runes.map { ($0, context) })
    }

    /// Whether the client still holds what Mito last sent for `part`. Mito's page must still be
    /// the current one: the user making another page current took the runes over too.
    private func holdsWhatMitoSent(
        _ part: ImportOutcome.Part, _ last: LastImport, session: ChampSelectSession
    ) async -> Result<Bool, LCUError> {
        do throws(LCUError) {
            switch part {
            case .runes:
                let page = RuneImporter.mitoPage(
                    in: try await connection.send(.perkPages), title: last.context.title)
                return .success(page?.current == true && page?.runePage == last.runes)
            case .spells:
                let me = session.myTeam.first {
                    $0.cellId != nil && $0.cellId == session.localPlayerCellId
                }
                // Unordered: the Flash rule may have swapped the pair Mito sent.
                let held = Set([me?.spell1Id, me?.spell2Id])
                return .success(held == Set([last.spells?.first, last.spells?.second]))
            case .items:
                let sets = try await connection.send(
                    .itemSets(summonerId: last.context.summonerId))
                return .success(
                    ItemSetImporter.mitoItemSet(in: sets, champion: last.context.champion)
                        == last.itemSet)
            }
        } catch {
            return .failure(error)
        }
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
        lastImports = [:]
        toldNothingToImport = false
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
            adaptations: adaptations, missing: missing, reimport: reimport)
    }
}

extension ImportReport {
    fileprivate subscript(part: ImportOutcome.Part) -> StepResult {
        get {
            switch part {
            case .runes: runes
            case .spells: spells
            case .items: items
            }
        }
        set {
            switch part {
            case .runes: runes = newValue
            case .spells: spells = newValue
            case .items: items = newValue
            }
        }
    }
}

extension StepResult {
    /// The client holds the pair Mito recommended: sent now, or already chosen.
    fileprivate var leftThePair: Bool {
        self == .applied || self == .skipped(.alreadySelected)
    }

    fileprivate var isNeedsConfirmation: Bool {
        if case .needsConfirmation = self { true } else { false }
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
