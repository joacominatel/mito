import SwiftUI

struct GameflowMenuSection: View {
    var body: some View {
        Text("Sin partida en curso", tableName: "Gameflow")
            .foregroundStyle(.secondary)
    }
}

#Preview {
    GameflowMenuSection()
        .padding()
}
