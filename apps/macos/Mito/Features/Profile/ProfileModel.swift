import Foundation
import LCUKit
import MitoCore
import Observation

/// Keeps the user's own match history in the personal store (§19.1): a sync on each connect
/// and on each entry to `EndOfGame`, one at a time.
@Observable
final class ProfileModel {
    enum SyncStatus: Equatable {
        case idle
        case syncing
        /// The games this sync added to the store.
        case synced(newGames: Int)
        case failed(SyncFailure)
    }

    enum SyncFailure: Error, Equatable {
        case client
        case storage
    }

    static let pageSize = 20
    static let backfillGames = 100

    private(set) var syncStatus: SyncStatus = .idle
    private let connection: any LCUConnection
    private let store: any PersonalStore
    @ObservationIgnored private var hasBackfilled = false

    init(connection: any LCUConnection, store: any PersonalStore) {
        self.connection = connection
        self.store = store
    }

    /// Returns once the connection's streams finish and the last pending sync settles.
    func run() async {
        // A trigger that arrives mid-sync queues one more sync; further ones fold into it.
        let (triggers, trigger) = AsyncStream.makeStream(
            of: Void.self, bufferingPolicy: .bufferingNewest(1))
        await withDiscardingTaskGroup { group in
            group.addTask {
                for await _ in triggers { await self.sync() }
            }
            await withDiscardingTaskGroup { sources in
                sources.addTask { await self.followPhases(trigger) }
                for await state in connection.states() where state == .connected {
                    trigger.yield()
                }
            }
            trigger.finish()
        }
    }

    private func followPhases(_ trigger: AsyncStream<Void>.Continuation) async {
        var last: GameflowPhase?
        for await event in connection.events([.gameflowPhase]) {
            guard let phase = try? GameflowPhase(event) else { continue }
            if phase == .endOfGame, last != .endOfGame { trigger.yield() }
            last = phase
        }
    }

    private func sync() async {
        // The PUUID only picks the local player out of each game; it is never kept or logged.
        guard let summoner = try? await connection.send(.currentSummoner),
            let puuid = summoner.puuid, !puuid.isEmpty
        else { return }
        syncStatus = .syncing
        do throws(SyncFailure) {
            let fetched = try await fetchHistory(localPUUID: puuid)
            let stored = try await storedGames(newest: fetched.count)
            // A stored game is final, and may hold the full game the page lacks.
            var matches: [MyMatch] = []
            for match in fetched where !stored.contains(match.game) {
                guard match.isIncomplete else {
                    matches.append(match)
                    continue
                }
                // One at a time; without the full game, the page's version still counts.
                let detail = try? await connection.send(
                    .matchHistoryGame(match.game, localPUUID: puuid))
                matches.append(detail?.match ?? match)
            }
            try await record(matches)
            hasBackfilled = true
            syncStatus = .synced(newGames: matches.count)
        } catch {
            syncStatus = .failed(error)
        }
    }

    /// Newest first, without repeats. The first sync of a run pages back to `backfillGames`.
    private func fetchHistory(localPUUID: String) async throws(SyncFailure) -> [MyMatch] {
        let limit = hasBackfilled ? Self.pageSize : Self.backfillGames
        var matches: [MyMatch] = []
        var seen: Set<GameID> = []
        for begin in stride(from: 0, to: limit, by: Self.pageSize) {
            let page: MatchHistoryPage
            do {
                page = try await connection.send(
                    .matchHistory(
                        begIndex: begin, endIndex: begin + Self.pageSize, localPUUID: localPUUID))
            } catch {
                throw .client
            }
            if page.matches.isEmpty { break }
            matches += page.matches.filter { seen.insert($0.game).inserted }
        }
        return matches
    }

    /// The store keeps only these games, so any of them already stored is among its newest.
    private func storedGames(newest count: Int) async throws(SyncFailure) -> Set<GameID> {
        do {
            return Set(try await store.matches(MyMatchQuery(limit: count)).map(\.game))
        } catch {
            throw .storage
        }
    }

    private func record(_ matches: [MyMatch]) async throws(SyncFailure) {
        do {
            try await store.record(matches)
        } catch {
            throw .storage
        }
    }
}

extension MyMatch {
    /// The history list can drop players; the full game is then worth one more request.
    fileprivate var isIncomplete: Bool {
        participants.count < 9 || (role != nil && opponent == nil)
    }
}

extension ProfileModel.SyncStatus {
    /// The one-line status under the Profile placeholder; `nil` before the first sync.
    var title: LocalizedStringResource? {
        switch self {
        case .idle: nil
        case .syncing: LocalizedStringResource("Sincronizando historial…", table: "Profile")
        case .synced(let newGames):
            LocalizedStringResource(
                "Historial al día: \(newGames) partidas nuevas", table: "Profile")
        case .failed(.client):
            LocalizedStringResource("No se pudo leer el historial del cliente", table: "Profile")
        case .failed(.storage):
            LocalizedStringResource("No se pudo guardar el historial", table: "Profile")
        }
    }

    var symbol: String? {
        switch self {
        case .idle, .syncing: nil
        case .synced: "checkmark.circle"
        case .failed: "exclamationmark.triangle"
        }
    }
}
