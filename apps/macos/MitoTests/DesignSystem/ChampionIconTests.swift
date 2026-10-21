import Foundation
import MitoCore
import Testing

@testable import Mito

/// Every state reads apart without color: an outline, a slash, or fading (§22.3).
struct ChampionIconTests {
    @Test(
        arguments: [
            (ChampionIcon.State.normal, ChampionIcon.Outline.none, false, 1.0, nil),
            (.hover, .dashed, false, 0.75, "en hover"),
            (.locked, .solid, false, 1.0, "lockeado"),
            (.banned, .none, true, 0.75, "baneado"),
            (.unavailable, .none, true, 0.4, "no disponible"),
        ] as [(ChampionIcon.State, ChampionIcon.Outline, Bool, Double, String?)])
    func eachStateHasItsLook(
        state: ChampionIcon.State, outline: ChampionIcon.Outline, muted: Bool, opacity: Double,
        spoken: String?
    ) {
        #expect(ChampionIcon.outline(state) == outline)
        #expect(ChampionIcon.isMuted(state) == muted)
        #expect(ChampionIcon.opacity(state) == opacity)
        #expect(ChampionIcon.stateText(state).map { String(localized: $0) } == spoken)
    }

    @Test func runesAreRoundAndTheRestSquare() {
        #expect(GameIcon.isRound(.perk(.init(rawValue: 8112))))
        #expect(GameIcon.isRound(.perkStyle(.init(rawValue: 8100))))
        #expect(!GameIcon.isRound(.champion(.init(rawValue: 103))))
        #expect(!GameIcon.isRound(nil))
    }
}
