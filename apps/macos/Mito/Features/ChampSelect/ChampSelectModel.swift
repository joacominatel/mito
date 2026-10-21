import LCUKit
import MitoCore
import Observation

@Observable
final class ChampSelectModel {
    private let connection: any LCUConnection
    let settings: @MainActor () -> ChampSelectSettings

    init(
        connection: any LCUConnection,
        settings: @escaping @MainActor () -> ChampSelectSettings = { ChampSelectSettings() }
    ) {
        self.connection = connection
        self.settings = settings
    }

    func run() async {}
}
