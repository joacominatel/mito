import SwiftUI
import Testing

@testable import Mito

/// The draft animates quietly, and not at all with Reduce Motion (§22.1).
struct MotionTests {
    @Test func reduceMotionTurnsTheDraftAnimationOff() {
        #expect(Motion.draft(reduceMotion: true) == nil)
    }

    @Test func withoutReduceMotionTheDraftAnimates() {
        #expect(Motion.draft(reduceMotion: false) != nil)
    }
}
