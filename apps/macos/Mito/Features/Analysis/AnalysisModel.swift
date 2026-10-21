import MitoCore
import Observation

/// The "Análisis" panel under the draft (§20.1): the chosen tab and the subject every tab reads.
@Observable
final class AnalysisModel {
    enum Tab: CaseIterable, Hashable {
        case matchup
        case composition
        case build
        case history

        /// Mi historial reads only the personal layer, so it works without a snapshot (§20.3).
        var needsSnapshot: Bool { self != .history }
    }

    /// Kept while the app runs, never saved to settings.
    var tab: Tab = .matchup

    private let champSelect: ChampSelectModel
    private let readStats: @MainActor () -> any StatsProvider

    init(
        champSelect: ChampSelectModel,
        stats: @escaping @MainActor () -> any StatsProvider = { ChampSelectModel.NoStats() }
    ) {
        self.champSelect = champSelect
        readStats = stats
    }

    /// `nil` outside champ select. Derived on read, like the recommendations, so the draft and
    /// a snapshot that opens mid-draft apply at once.
    var subject: AnalysisSubject? {
        guard let draft = champSelect.draft else { return nil }
        return AnalysisSubject.derive(
            draft: draft, role: champSelect.scoringRole, enemyRoles: champSelect.enemyRoles,
            topPick: { champSelect.topPick }, stats: readStats(),
            personal: champSelect.personal, names: champSelect.reasonNames,
            gameData: champSelect.gameData)
    }

    /// The chosen tab needs the snapshot and none is open: the panel shows its empty state.
    var isMissingSnapshot: Bool {
        tab.needsSnapshot && readStats().meta == nil
    }
}
