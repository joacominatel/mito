import Foundation
import MitoAssets
import MitoCore
import MitoEngine

/// What the Build tab shows (§20.2): the loadout the importer would send for the subject, part by
/// part, each option with its winrate, sample, and reason.
struct BuildContent: Equatable {
    enum State: Equatable {
        case noChampion
        /// ARAM has no build data (§20.3): only a fixed page from the champion's overrides.
        case aram(fixedPage: BuildOption?)
        /// No role to import for, or no `champ_role_stats` row for it.
        case noData
        case loadout([BuildPart])
    }

    /// How sure the tab can be that this is what gets imported.
    enum Framing: Equatable {
        /// Locked, or hovered with "Importar al hacer hover".
        case imports
        /// Hovered: the importer waits for the lock.
        case importsOnLock
        /// The top pick recommendation: nothing is picked yet.
        case ifYouPick
    }

    struct Opponent: Equatable {
        let name: String
        /// An inferred lane opponent is a guess and the tab says so (§12.3).
        let isInferred: Bool
    }

    let champion: String
    /// `nil` in ARAM and when no role has data.
    let role: Role?
    let framing: Framing
    /// Set when some imported part adapted to the lane opponent.
    let opponent: Opponent?
    /// The enemy profiles some imported part adapted to.
    let profiles: [EnemyProfile]
    let state: State
}

/// One loadout part: runes, spells, one item layer, the situational items, or the skill order.
struct BuildPart: Identifiable, Equatable {
    enum ID: Hashable {
        case runes
        case spells
        case items(BuildLayer)
        /// A block of the override's fixed set, by position.
        case fixedItems(Int)
        case situational
        case skippedItems
        case skillOrder
    }

    enum Source: Equatable {
        case general
        case adaptedToOpponent
        case adaptedToProfiles([EnemyProfile])
        /// The champion override's fixed page, pair, or set.
        case override
        /// The override asks for a fixed choice it does not have: the general one goes (§21.5).
        case generalWithoutFixed
        /// The override's "no importar" items.
        case skippedByOverride
        /// Flag counters and profile items (§18.7).
        case situational
    }

    let id: ID
    let title: String
    let source: Source
    /// `false` when Settings turns the part off; the skill order is never imported.
    let isImported: Bool
    /// Several only for the situational items and a fixed set's block.
    let chosen: [BuildOption]
    let alternatives: [BuildOption]
}

struct BuildOption: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String?
    /// `nil` for a fixed choice, which has no sample behind it.
    let level: SampleLevel?
    let reasons: [Reason]
}

extension BuildContent {
    /// Follows `ImportModel`: the client-assigned role or the champion's most played one, its lane
    /// opponent and enemy profile, the override of (champion, role), and `ImportModel.plan`.
    static func derive(_ subject: AnalysisSubject, settings: ImportSettings) -> BuildContent {
        let names = BuildNames(gameData: subject.gameData, reasonNames: subject.names)
        guard let champion = subject.champion else {
            return BuildContent(
                champion: "", role: nil, framing: .imports, opponent: nil, profiles: [],
                state: .noChampion)
        }
        let framing: Framing =
            switch champion.source {
            case .locked: .imports
            case .hovered: settings.importOnHover ? .imports : .importsOnLock
            case .recommended: .ifYouPick
            }
        func content(role: Role?, state: State) -> BuildContent {
            BuildContent(
                champion: names.champion(champion.id), role: role, framing: framing,
                opponent: nil, profiles: [], state: state)
        }

        if subject.queue == .aram {
            // ARAM has no role: the first role, in `Role` order, with a fixed page saved.
            let page = Role.allCases.lazy.compactMap { role in
                subject.personal.overrides.first {
                    $0.champion == champion.id && $0.role == role
                }?.fixedPage
            }.first
            return content(role: nil, state: .aram(fixedPage: page.map { names.option(fixed: $0) }))
        }

        let stats = subject.stats
        let enemies = subject.enemies.map(\.draftSlot)
        let me = subject.allies.first(where: \.isMe)
        guard
            let role = me?.role?.assignedRole
                ?? ImportModel.mostPlayedRole(of: champion.id, in: stats)
        else { return content(role: nil, state: .noData) }

        let opponent = ImportModel.laneOpponent(among: enemies, in: role, stats: stats)
        let profile = Composition.enemyProfile(
            of: Composition.teamProfile(
                of: Composition.members(of: enemies, stats: stats), stats: stats),
            rules: stats.meta?.profileRules)
        let general = LoadoutSelection.general(for: champion.id, role: role, stats: stats)
        let adapted = LoadoutSelection.adapted(
            for: champion.id, role: role, opponent: opponent, enemyProfile: profile,
            enemies: subject.enemies.compactMap(\.champion), stats: stats)
        let override = subject.personal.overrides.first {
            $0.champion == champion.id && $0.role == role
        }
        let plan = ImportModel.plan(
            general: general.loadout, adapted: adapted.loadout, override: override,
            settings: settings)
        let loadout = plan.loadout
        guard loadout.runes != nil || loadout.spells != nil || loadout.itemSet != nil else {
            return content(role: role, state: .noData)
        }

        let parts = BuildParts(
            names: names, settings: settings, plan: plan, adapted: adapted,
            generalBreakdown: LoadoutSelection.breakdown(
                of: general, for: champion.id, role: role, enemyProfile: [], stats: stats),
            adaptedBreakdown: LoadoutSelection.breakdown(
                of: adapted, for: champion.id, role: role, enemyProfile: profile, stats: stats)
        ).all()

        let imported = parts.filter(\.isImported).map(\.source)
        let adaptedOpponent = opponent.flatMap { id -> Opponent? in
            guard imported.contains(.adaptedToOpponent) else { return nil }
            let slot = subject.enemies.first { $0.champion == id }
            return Opponent(
                name: names.champion(id), isInferred: slot?.role?.assignedRole != role)
        }
        var profiles: [EnemyProfile] = []
        for case .adaptedToProfiles(let adaptedProfiles) in imported {
            for profile in adaptedProfiles where !profiles.contains(profile) {
                profiles.append(profile)
            }
        }
        return BuildContent(
            champion: names.champion(champion.id), role: role, framing: framing,
            opponent: adaptedOpponent, profiles: profiles, state: .loadout(parts))
    }
}

/// Picks each part from the general or the adapted loadout as the plan did.
private struct BuildParts {
    let names: BuildNames
    let settings: ImportSettings
    let plan: ImportModel.Plan
    let adapted: GeneralLoadout
    let generalBreakdown: LoadoutBreakdown
    let adaptedBreakdown: LoadoutBreakdown

    func all() -> [BuildPart] {
        [runes(), spells()].compactMap(\.self) + items() + [skillOrder()].compactMap(\.self)
    }

    private func breakdown(_ part: ImportOutcome.Part) -> LoadoutBreakdown {
        plan.general.contains(part) ? generalBreakdown : adaptedBreakdown
    }

    private func source(_ part: ImportOutcome.Part, _ loadoutPart: LoadoutPart) -> BuildPart.Source
    {
        switch plan.origins[part] {
        case .override?: return .override
        case .noFixedChoice?: return .generalWithoutFixed
        case nil: break
        }
        if plan.general.contains(part) { return .general }
        var profiles: [EnemyProfile] = []
        for reason in adapted.loadout.explanation {
            switch reason.kind {
            case .adaptedToOpponent(loadoutPart, _, _): return .adaptedToOpponent
            case .adaptedToProfile(loadoutPart, let profile, _): profiles.append(profile)
            default: continue
            }
        }
        return profiles.isEmpty ? .general : .adaptedToProfiles(profiles)
    }

    private func runes() -> BuildPart? {
        let title = String(localized: "Runas", table: "Build")
        let source = source(.runes, .runes)
        if source == .override, let page = plan.loadout.runes {
            return BuildPart(
                id: .runes, title: title, source: source, isImported: settings.importRunes,
                chosen: [names.option(fixed: page)], alternatives: [])
        }
        return breakdown(.runes).runes.map {
            part(.runes, title, source, settings.importRunes, $0, .runes, names.option)
        }
    }

    private func spells() -> BuildPart? {
        let title = String(localized: "Spells", table: "Build")
        let source = source(.spells, .spells)
        if source == .override, let pair = plan.loadout.spells {
            return BuildPart(
                id: .spells, title: title, source: source, isImported: settings.importSpells,
                chosen: [names.option(fixed: pair)], alternatives: [])
        }
        return breakdown(.spells).spells.map {
            part(.spells, title, source, settings.importSpells, $0, .spells, names.option)
        }
    }

    private func items() -> [BuildPart] {
        let isImported = settings.importItemSets
        if plan.skipsItems {
            return [
                BuildPart(
                    id: .skippedItems, title: String(localized: "Ítems", table: "Build"),
                    source: .skippedByOverride, isImported: isImported, chosen: [],
                    alternatives: [])
            ]
        }
        guard let itemSet = plan.loadout.itemSet else { return [] }
        if plan.origins[.items] == .override {
            return itemSet.blocks.enumerated().map { index, block in
                BuildPart(
                    id: .fixedItems(index), title: block.title, source: .override,
                    isImported: isImported, chosen: [names.option(fixed: block.items)],
                    alternatives: [])
            }
        }
        let breakdown = breakdown(.items)
        return itemSet.blocks.compactMap { block -> BuildPart? in
            if block.title == LoadoutSelection.situationalBlockTitle {
                return situational(block, isImported: isImported)
            }
            guard let layer = BuildLayer(rawValue: block.title),
                let options = breakdown.itemLayers[layer]
            else { return nil }
            return part(
                .items(layer), names.layer(layer), source(.items, .items(layer)), isImported,
                options, .items(layer), names.option)
        }
    }

    private func situational(_ block: ItemSet.Block, isImported: Bool) -> BuildPart {
        let options = block.items.map { item in
            let reasons = adapted.loadout.explanation.filter {
                switch $0.kind {
                case .countersFlag(item.id, _, _), .situationalItem(item.id, _, _, _, _): true
                default: false
                }
            }
            return BuildOption(
                id: "\(item.id.rawValue)", title: names.item(item.id), subtitle: nil,
                level: reasons.compactMap(\.sample).min(), reasons: reasons)
        }
        return BuildPart(
            id: .situational, title: String(localized: "Situacionales", table: "Build"),
            source: .situational, isImported: isImported, chosen: options, alternatives: [])
    }

    private func skillOrder() -> BuildPart? {
        adaptedBreakdown.skillOrder.map {
            part(
                .skillOrder, String(localized: "Habilidades", table: "Build"), .general, false, $0,
                .skillOrder, names.option)
        }
    }

    private func part<Value>(
        _ id: BuildPart.ID, _ title: String, _ source: BuildPart.Source, _ isImported: Bool,
        _ options: LoadoutPartOptions<Value>, _ loadoutPart: LoadoutPart,
        _ describe: (Value) -> (id: String, title: String, subtitle: String?)
    ) -> BuildPart {
        func option(_ stats: LoadoutOptionStats<Value>) -> BuildOption {
            let described = describe(stats.value)
            return BuildOption(
                id: described.id, title: described.title, subtitle: described.subtitle,
                level: stats.level,
                reasons: [
                    // The level is the option's own indicator, so the reason carries no mark.
                    Reason(
                        kind: .generalChoice(
                            part: loadoutPart, usage: stats.usage, winrate: stats.winrate,
                            games: stats.games),
                        sample: nil)
                ])
        }
        return BuildPart(
            id: id, title: title, source: source, isImported: isImported,
            chosen: [option(options.chosen)], alternatives: options.alternatives.map(option))
    }
}

/// The client's names, or numbered fallbacks while its data loads.
struct BuildNames {
    let gameData: GameData?
    let reasonNames: ReasonNames

    func champion(_ id: ChampionID) -> String { reasonNames.champion(id) }

    func item(_ id: ItemID) -> String {
        if let name = gameData?.item(id)?.name, !name.isEmpty { return name }
        return reasonNames.item(id)
    }

    func perk(_ id: PerkID) -> String {
        if let name = gameData?.perk(id)?.name, !name.isEmpty { return name }
        return String(localized: "Runa \(String(id.rawValue))", table: "Build")
    }

    func style(_ id: PerkStyleID) -> String {
        if let name = gameData?.perkStyle(id)?.name, !name.isEmpty { return name }
        return String(localized: "Rama \(String(id.rawValue))", table: "Build")
    }

    func spell(_ id: SummonerSpellID) -> String {
        if let name = gameData?.spell(id)?.name, !name.isEmpty { return name }
        return String(localized: "Spell \(String(id.rawValue))", table: "Build")
    }

    func layer(_ layer: BuildLayer) -> String {
        switch layer {
        case .start: String(localized: "Inicio", table: "Build")
        case .core: String(localized: "Núcleo", table: "Build")
        case .boots: String(localized: "Botas", table: "Build")
        case .fourth: String(localized: "4.º ítem", table: "Build")
        case .fifth: String(localized: "5.º ítem", table: "Build")
        case .sixth: String(localized: "6.º ítem", table: "Build")
        }
    }

    /// The keystone, then the two trees and the other five runes; the shards are left out.
    func option(_ page: RunePage) -> (id: String, title: String, subtitle: String?) {
        let runes = page.perks.dropFirst().prefix(5).map(perk).joined(separator: " · ")
        let trees = String(
            localized: "\(style(page.primaryStyle)) + \(style(page.subStyle))", table: "Build")
        return (
            page.perks.map { "\($0.rawValue)" }.joined(separator: "-"),
            page.perks.first.map(perk) ?? trees, runes.isEmpty ? trees : "\(trees) · \(runes)"
        )
    }

    func option(_ pair: SpellPair) -> (id: String, title: String, subtitle: String?) {
        (
            "\(pair.first.rawValue)-\(pair.second.rawValue)",
            String(localized: "\(spell(pair.first)) + \(spell(pair.second))", table: "Build"), nil
        )
    }

    func option(_ items: [ItemSet.Block.Item]) -> (id: String, title: String, subtitle: String?) {
        let title = items.map { item in
            let name = self.item(item.id)
            return item.count > 1
                ? String(localized: "\(name) ×\(item.count)", table: "Build") : name
        }
        return (
            items.map { "\($0.id.rawValue)x\($0.count)" }.joined(separator: "-"),
            title.joined(separator: " · "), nil
        )
    }

    func option(_ order: SkillOrder) -> (id: String, title: String, subtitle: String?) {
        let maxOrder = order.maxOrder.map(\.rawValue).joined(separator: " > ")
        let opening = order.sequence.prefix(3).map(\.rawValue).joined(separator: " · ")
        return (
            order.maxOrder.map(\.rawValue).joined() + "-" + order.sequence.map(\.rawValue).joined(),
            maxOrder,
            opening.isEmpty ? nil : String(localized: "Empieza \(opening)", table: "Build")
        )
    }

    func option(fixed page: RunePage) -> BuildOption { fixed(option(page)) }
    func option(fixed pair: SpellPair) -> BuildOption { fixed(option(pair)) }
    func option(fixed items: [ItemSet.Block.Item]) -> BuildOption { fixed(option(items)) }

    private func fixed(_ described: (id: String, title: String, subtitle: String?)) -> BuildOption {
        BuildOption(
            id: described.id, title: described.title, subtitle: described.subtitle, level: nil,
            reasons: [])
    }
}

extension AnalysisSubject.SlotRole {
    fileprivate var assignedRole: Role? {
        if case .assigned(let role) = self { role } else { nil }
    }
}

extension AnalysisSubject.Slot {
    /// The importer reads the client's roles only and infers the rest itself.
    fileprivate var draftSlot: DraftSlot {
        let assigned = role?.assignedRole
        return DraftSlot(
            cellId: id, champion: champion, hover: hover, role: assigned,
            roleConfidence: assigned == nil ? 0 : 1)
    }
}
