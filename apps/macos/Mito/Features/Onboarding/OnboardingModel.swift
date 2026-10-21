import Foundation
import MitoAssets
import MitoCore
import Observation

/// The General tab (§21.1): the champion pool per role (§19.1) and the Flash position detected
/// from the stored history (§21.4). The champions come from the shared `GameData` (§9.3).
@Observable
final class OnboardingModel {
    enum FlashSlot: Equatable {
        case d
        case f
    }

    /// The recent games with Flash, by the slot it was in.
    struct FlashDetection: Equatable {
        let inD: Int
        let inF: Int

        var games: Int { inD + inF }

        /// `nil` on a tie, which includes no games with Flash.
        var majority: FlashSlot? {
            inD == inF ? nil : inD > inF ? .d : .f
        }

        var majorityGames: Int { max(inD, inF) }
    }

    enum Loading<Value: Equatable>: Equatable {
        case loading
        case loaded(Value)
        case unavailable
    }

    enum PoolProblem: Equatable {
        /// The pool could not be read: editing stays off until a read works.
        case readFailed
        /// The last change was not saved and was undone.
        case saveFailed
    }

    /// How many recent games the Flash detection reads.
    static let flashSample = 20
    static let flashSpell = SummonerSpellID(rawValue: 4)

    var role: Role = .top
    var query = ""
    /// The role's pool in priority order: the first is the main.
    private(set) var pool: [ChampionID] = []
    private(set) var poolProblem: PoolProblem?
    private(set) var flash: Loading<FlashDetection> = .loading

    private let store: any PersonalStore
    private let readGameData: @MainActor () -> GameData?

    init(
        store: any PersonalStore = UnavailablePersonalStore(),
        gameData: @autoclosure @escaping @MainActor () -> GameData? = nil
    ) {
        self.store = store
        readGameData = gameData
    }

    /// The import reads the detected slot, so it is detected here rather than when the tab opens;
    /// the shell detects again after each history sync.
    func run() async {
        await detectFlash()
    }

    /// The client's champions by name; `.unavailable` until the shared data first loads.
    var catalog: Loading<[Champion]> {
        guard let gameData = readGameData() else { return .unavailable }
        return .loaded(
            gameData.allChampions
                .filter { $0.id.rawValue > 0 && !$0.name.isEmpty }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
    }

    var canEditPool: Bool { poolProblem != .readFailed }

    /// Adding needs the client's champions to pick from.
    var canAddToPool: Bool {
        guard case .loaded = catalog else { return false }
        return canEditPool
    }

    /// The catalog without the pool, filtered by `query`.
    var searchResults: [Champion] {
        guard case .loaded(let champions) = catalog else { return [] }
        let query = query.trimmingCharacters(in: .whitespaces)
        return champions.filter {
            !pool.contains($0.id) && (query.isEmpty || $0.name.localizedStandardContains(query))
        }
    }

    func name(of champion: ChampionID) -> String {
        if let name = readGameData()?.champion(champion)?.name, !name.isEmpty { return name }
        return String(localized: "Campeón \(String(champion.rawValue))", table: "Onboarding")
    }

    func loadPool() async {
        let role = role
        do {
            let entries = try await store.pool(for: role)
            guard role == self.role else { return }
            pool = entries.sorted { $0.priority < $1.priority }.map(\.champion)
            poolProblem = nil
        } catch {
            guard role == self.role else { return }
            pool = []
            poolProblem = .readFailed
        }
    }

    func add(_ champion: ChampionID) async {
        guard !pool.contains(champion) else { return }
        await save(pool + [champion])
    }

    func remove(_ champion: ChampionID) async {
        await save(pool.filter { $0 != champion })
    }

    func moveUp(_ champion: ChampionID) async {
        await move(champion, by: -1)
    }

    func moveDown(_ champion: ChampionID) async {
        await move(champion, by: 1)
    }

    func detectFlash() async {
        do {
            let matches = try await store.matches(MyMatchQuery(limit: Self.flashSample))
            flash = .loaded(
                FlashDetection(
                    inD: matches.count { $0.spells.first == Self.flashSpell },
                    inF: matches.count { $0.spells.second == Self.flashSpell }))
        } catch {
            flash = .unavailable
        }
    }

    var flashSummary: LocalizedStringResource {
        switch flash {
        case .loading:
            LocalizedStringResource("Leyendo tus partidas…", table: "Onboarding")
        case .unavailable:
            LocalizedStringResource("No se pudo leer tu historial", table: "Onboarding")
        case .loaded(let detection):
            switch detection.majority {
            case .d:
                LocalizedStringResource(
                    "Detectado: D en \(detection.majorityGames) de \(detection.games) partidas",
                    table: "Onboarding")
            case .f:
                LocalizedStringResource(
                    "Detectado: F en \(detection.majorityGames) de \(detection.games) partidas",
                    table: "Onboarding")
            case nil where detection.games == 0:
                LocalizedStringResource(
                    "Sin partidas con Flash en tu historial", table: "Onboarding")
            case nil:
                LocalizedStringResource(
                    "Empate: D y F en \(detection.inD) partidas cada una", table: "Onboarding")
            }
        }
    }

    /// The slot the importer should put Flash in; `auto` follows the detected majority, and is
    /// `nil` when there is none.
    func resolvedFlashSlot(_ setting: ImportSettings.FlashPosition) -> FlashSlot? {
        switch setting {
        case .d: .d
        case .f: .f
        case .auto:
            if case .loaded(let detection) = flash { detection.majority } else { nil }
        }
    }

    private func move(_ champion: ChampionID, by offset: Int) async {
        guard let index = pool.firstIndex(of: champion), pool.indices.contains(index + offset)
        else { return }
        var reordered = pool
        reordered.swapAt(index, index + offset)
        await save(reordered)
    }

    /// Shows the change at once; a failed save puts the previous pool back.
    private func save(_ champions: [ChampionID]) async {
        guard poolProblem != .readFailed else { return }
        let role = role
        let previous = pool
        pool = champions
        do {
            try await store.setPool(champions, for: role)
            poolProblem = nil
        } catch {
            guard role == self.role else { return }
            pool = previous
            poolProblem = .saveFailed
        }
    }
}
