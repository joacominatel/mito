import LCUKit
import Observation

@Observable
final class ImportModel {
    private let connection: any LCUConnection

    init(connection: any LCUConnection) {
        self.connection = connection
    }

    func run() async {}
}
