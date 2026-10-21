import LCUKit
import MitoCore
import Observation

@Observable
final class OnboardingModel {
    private let connection: any LCUConnection
    private let store: any PersonalStore

    init(connection: any LCUConnection, store: any PersonalStore = UnavailablePersonalStore()) {
        self.connection = connection
        self.store = store
    }

    func run() async {}
}
