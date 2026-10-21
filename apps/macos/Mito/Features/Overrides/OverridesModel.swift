import Foundation
import MitoAssets
import MitoCore
import Observation

/// Per-champion, per-role overrides (§21.5). Static data comes in with each call: the view
/// reads the shared `GameData` (§9.3).
@Observable
final class OverridesModel {
    enum Failure: Equatable {
        case load
        case save
        case delete
    }

    private(set) var overrides: [ChampionOverride] = []
    /// Filters both the overrides and the champion list by name.
    var searchText = ""
    /// The item search of the fixed set editor.
    var itemQuery = ""
    /// The open editor; `nil` when none is.
    var draft: OverrideDraft?
    private(set) var failure: Failure?

    /// What `draft` was when opened, to tell whether it has unsaved changes.
    @ObservationIgnored private var baseline: OverrideDraft?
    private let store: any PersonalStore

    init(store: any PersonalStore = UnavailablePersonalStore()) {
        self.store = store
    }

    func run() async {
        await load()
    }

    func load() async {
        do {
            overrides = try await store.overrides()
            if failure == .load { failure = nil }
        } catch {
            failure = .load
        }
    }

    // MARK: Lists

    /// Every champion whose name matches the search, by name.
    func champions(in gameData: GameData) -> [Champion] {
        gameData.allChampions
            .filter { matchesSearch($0.name) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The stored overrides whose champion matches the search, by name, then role.
    func listedOverrides(in gameData: GameData) -> [ChampionOverride] {
        let roles = Role.allCases
        return
            overrides
            .map { (override: $0, name: name(of: $0.champion, in: gameData)) }
            .filter { matchesSearch($0.name) }
            .sorted {
                switch $0.name.localizedStandardCompare($1.name) {
                case .orderedAscending: true
                case .orderedDescending: false
                case .orderedSame:
                    (roles.firstIndex(of: $0.override.role) ?? 0)
                        < (roles.firstIndex(of: $1.override.role) ?? 0)
                }
            }
            .map(\.override)
    }

    func name(of champion: ChampionID, in gameData: GameData) -> String {
        if let name = gameData.champion(champion)?.name, !name.isEmpty { return name }
        return String(localized: "Campeón \(String(champion.rawValue))", table: "Overrides")
    }

    /// The spells Summoner's Rift allows, by name.
    func classicSpells(in gameData: GameData) -> [SummonerSpell] {
        gameData.allSpells
            .filter { $0.gameModes.contains("CLASSIC") }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Items whose name matches `itemQuery`, by name; nothing while the query is empty.
    func itemResults(in gameData: GameData) -> [Item] {
        let query = itemQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        return gameData.allItems
            .filter { !$0.name.isEmpty && $0.name.localizedStandardContains(query) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .prefix(Self.itemResultLimit)
            .map(\.self)
    }

    // MARK: Editing

    var isEditing: Bool {
        get { draft != nil }
        set { if !newValue { close() } }
    }

    var hasChanges: Bool { draft != baseline }

    /// Whether the open (champion, role) has a stored override to delete.
    var isStored: Bool {
        guard let draft else { return false }
        return stored(draft.champion, draft.role) != nil
    }

    /// Opens the editor on the stored override, or on the defaults when there is none.
    /// `role` defaults to the champion's first stored role, then top.
    func open(_ champion: ChampionID, role: Role? = nil, styles: [PerkStyle]) {
        let role = role ?? overrides.first { $0.champion == champion }?.role ?? .top
        let override =
            stored(champion, role) ?? ChampionOverride(champion: champion, role: role)
        draft = OverrideDraft(override, styles: styles)
        baseline = draft
        itemQuery = ""
        if failure != .load { failure = nil }
    }

    /// Unsaved changes stay with their role: switch only from a clean draft.
    func switchRole(to role: Role, styles: [PerkStyle]) {
        guard let draft, !hasChanges, role != draft.role else { return }
        open(draft.champion, role: role, styles: styles)
    }

    func close() {
        draft = nil
        baseline = nil
    }

    func issues(styles: [PerkStyle]) -> [OverrideIssue] {
        draft?.issues(styles: styles) ?? []
    }

    func canSave(styles: [PerkStyle]) -> Bool {
        hasChanges && draft?.override(styles: styles) != nil
    }

    /// Closes the editor on success; on failure it stays open with `failure` set.
    func save(styles: [PerkStyle]) async {
        guard hasChanges, let override = draft?.override(styles: styles) else { return }
        do {
            try await store.save(override)
        } catch {
            failure = .save
            return
        }
        overrides.removeAll { $0.champion == override.champion && $0.role == override.role }
        overrides.append(override)
        // The store's order, so `open` without a role picks what it would after a relaunch.
        let roles = Role.allCases
        overrides.sort {
            ($0.champion.rawValue, roles.firstIndex(of: $0.role) ?? 0)
                < ($1.champion.rawValue, roles.firstIndex(of: $1.role) ?? 0)
        }
        failure = nil
        close()
    }

    func delete() async {
        guard let draft else { return }
        do {
            try await store.deleteOverride(champion: draft.champion, role: draft.role)
        } catch {
            failure = .delete
            return
        }
        overrides.removeAll { $0.champion == draft.champion && $0.role == draft.role }
        failure = nil
        close()
    }

    private static let itemResultLimit = 50

    private func stored(_ champion: ChampionID, _ role: Role) -> ChampionOverride? {
        overrides.first { $0.champion == champion && $0.role == role }
    }

    private func matchesSearch(_ name: String) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return query.isEmpty || name.localizedStandardContains(query)
    }
}
