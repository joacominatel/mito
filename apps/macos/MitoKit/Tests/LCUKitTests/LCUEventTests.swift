import LCUKit
import Testing

struct LCUEventTests {
    @Test(arguments: [
        ("Create", LCUEvent.EventType.create), ("Update", .update), ("Delete", .delete),
    ])
    func mapsKnownEventTypes(raw: String, type: LCUEvent.EventType) {
        #expect(LCUEvent.EventType(raw) == type)
    }

    @Test func keepsAnUnknownEventType() {
        #expect(LCUEvent.EventType("Patch") == .unknown("Patch"))
    }
}
