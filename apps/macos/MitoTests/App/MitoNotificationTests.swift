import Testing

@testable import Mito

struct MitoNotificationTests {
    @Test func aFoundMatchHasItsOwnIdentifier() {
        #expect(MitoNotification.matchFound.identifier == "matchFound")
    }
}
