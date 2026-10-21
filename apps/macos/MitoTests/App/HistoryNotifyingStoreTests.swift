import Foundation
import MitoCore
import Synchronization
import Testing

@testable import Mito

/// Every call but `record` reaches the base unchanged and never fires the hook.
struct HistoryNotifyingStoreTests {
    private nonisolated final class Hook: Sendable {
        private let fired = Mutex(0)
        var count: Int { fired.withLock { $0 } }

        func store(over base: any PersonalStore) -> HistoryNotifyingStore {
            HistoryNotifyingStore(base: base) { self.fired.withLock { $0 += 1 } }
        }
    }

    private let ahri = ChampionID(rawValue: 103)
    private let zed = ChampionID(rawValue: 238)

    @Test func overridesPassThrough() async throws {
        let hook = Hook()
        let base = OverridesTestStore()
        let store = hook.store(over: base)

        try await store.save(ChampionOverride(champion: ahri, role: .middle, isFavorite: true))
        try await store.save(ChampionOverride(champion: zed, role: .jungle))
        try await store.deleteOverride(champion: zed, role: .jungle)

        #expect(try await store.overrides().map(\.champion) == [ahri])
        #expect(await base.stored.map(\.isFavorite) == [true])
        #expect(hook.count == 0)
    }

    @Test func thePoolPassesThrough() async throws {
        let hook = Hook()
        let store = hook.store(over: PoolTestStore())

        try await store.setPool([zed, ahri], for: .middle)

        // The fake answers out of order on purpose; priority carries the order.
        let pool = try await store.pool(for: .middle)
        #expect(pool.sorted { $0.priority < $1.priority }.map(\.champion) == [zed, ahri])
        #expect(try await store.pool(for: .top).isEmpty)
        #expect(hook.count == 0)
    }

    @Test func theImportLogPassesThroughAndDeleteAllEmptiesIt() async throws {
        let hook = Hook()
        let store = hook.store(over: ImportTestStore())
        let entry = ImportLogEntry(
            timestamp: Date(timeIntervalSince1970: 0), game: nil, champion: ahri, part: .runes,
            outcome: .applied, detail: nil)

        try await store.appendImportLog(entry)
        #expect(try await store.importLog(limit: 10) == [entry])

        try await store.deleteAll()
        #expect(try await store.importLog(limit: 10).isEmpty)
        #expect(hook.count == 0)
    }

    @Test func readsAndFailuresComeFromTheBase() async {
        let hook = Hook()
        let store = hook.store(over: HistoryTestStore(failure: .readFailed))

        await #expect(throws: PersonalStoreError.readFailed) {
            _ = try await store.matches(MyMatchQuery())
        }
        #expect(hook.count == 0)
    }
}
