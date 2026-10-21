import SwiftUI

struct ChampionsView: View {
    var body: some View {
        ContentUnavailableView {
            Label {
                Text("Sin datos del parche", tableName: "Champions")
            } icon: {
                Image(systemName: "person.3")
            }
        }
    }
}

#Preview {
    ChampionsView()
}
