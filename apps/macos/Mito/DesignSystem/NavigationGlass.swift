import SwiftUI

/// Liquid Glass for the navigation layer (§22.1): macOS 26 and later get the system's glass, and
/// earlier versions a regular material in the same place. Never on content.
extension View {
    /// A floating control or panel: glass in `shape`, or a regular material in the same shape.
    @ViewBuilder
    func navigationGlass(in shape: some Shape) -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
        }
    }

    /// The window's toolbar over this column. On macOS 26 the system draws the sidebar and the
    /// toolbar in glass, so it only sets the hard scroll edge dense content wants under it.
    @ViewBuilder
    func navigationBarGlass() -> some View {
        if #available(macOS 26, *) {
            scrollEdgeEffectStyle(.hard, for: .top)
        } else {
            toolbarBackground(.regularMaterial, for: .windowToolbar)
                .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        }
    }
}
