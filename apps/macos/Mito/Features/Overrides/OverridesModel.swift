import MitoCore
import Observation

@Observable
final class OverridesModel {
    private let store: any PersonalStore

    init(store: any PersonalStore = UnavailablePersonalStore()) {
        self.store = store
    }

    func run() async {}
}
