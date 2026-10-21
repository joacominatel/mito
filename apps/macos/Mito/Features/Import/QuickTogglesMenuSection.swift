import SwiftUI

/// §22.4 quick toggles: auto-accept, import runes, import items.
struct QuickTogglesMenuSection: View {
    var body: some View {
        Text("Toggles rápidos: próximamente", tableName: "Import")
            .foregroundStyle(.secondary)
    }
}

#Preview {
    QuickTogglesMenuSection()
        .padding()
}
