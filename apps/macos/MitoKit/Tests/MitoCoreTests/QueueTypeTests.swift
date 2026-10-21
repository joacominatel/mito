import MitoCore
import Testing

struct QueueTypeTests {
    @Test(arguments: [
        (400, QueueType.normalDraft), (420, .rankedSolo), (430, .normalBlind), (440, .rankedFlex),
        (450, .aram),
    ])
    func mapsKnownQueueIDs(id: Int, queue: QueueType) {
        #expect(QueueType(queueID: QueueID(rawValue: id)) == queue)
        #expect(queue.queueID == QueueID(rawValue: id))
    }

    @Test func keepsAnUnknownQueueID() {
        let queue = QueueType(queueID: QueueID(rawValue: 1700))
        #expect(queue == .other(QueueID(rawValue: 1700)))
        #expect(queue.queueID == QueueID(rawValue: 1700))
    }
}
