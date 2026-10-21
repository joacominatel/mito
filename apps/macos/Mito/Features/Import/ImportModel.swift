import LCUKit
import MitoCore
import Observation

@Observable
final class ImportModel {
    private let connection: any LCUConnection
    let settings: @MainActor () -> ImportSettings

    init(
        connection: any LCUConnection,
        settings: @escaping @MainActor () -> ImportSettings = { ImportSettings() }
    ) {
        self.connection = connection
        self.settings = settings
    }

    func run() async {}
}
