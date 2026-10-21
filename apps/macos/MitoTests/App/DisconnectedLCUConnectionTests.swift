import LCUKit
import Testing

@testable import Mito

struct DisconnectedLCUConnectionTests {
    @Test func reportsSearchingOnly() async {
        var states: [ConnectionState] = []
        for await state in DisconnectedLCUConnection().states() { states.append(state) }

        #expect(states == [.searching])
    }

    @Test func sendThrowsNotConnected() async {
        await #expect(throws: LCUError.notConnected) {
            _ = try await DisconnectedLCUConnection().send(
                LCUEndpoint<LCUNoContent>(method: .get, path: "/probe"))
        }
    }

    @Test func eventsFinishWithoutEvents() async {
        var count = 0
        for await _ in DisconnectedLCUConnection().events(Set(LCUTopic.allCases)) { count += 1 }

        #expect(count == 0)
    }
}
