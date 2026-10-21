import Foundation
import Testing

@testable import Mito

struct SidebarDestinationTests {
    @Test func matchesTheSpecifiedSidebar() {
        let titles = SidebarDestination.allCases.map { String(localized: $0.title) }

        #expect(titles == ["Ahora", "Campeones", "Mi perfil", "Overrides"])
        #expect(
            SidebarDestination.allCases == [.now, .champions, .profile, .overrides])
    }
}
