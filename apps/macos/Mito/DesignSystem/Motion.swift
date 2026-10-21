import SwiftUI

/// The draft's motion (§22.1): short and quiet, and none at all with Reduce Motion.
enum Motion {
    static func draft(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .snappy(duration: 0.25)
    }
}

extension View {
    /// Animates what changes with `value`, unless Reduce Motion is on.
    func draftAnimation<Value: Equatable>(value: Value) -> some View {
        modifier(DraftAnimation(value: value))
    }
}

private struct DraftAnimation<Value: Equatable>: ViewModifier {
    let value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(Motion.draft(reduceMotion: reduceMotion), value: value)
    }
}
