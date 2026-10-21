import SwiftUI

struct NowView: View {
    var body: some View {
        ContentUnavailableView {
            Label {
                Text("Esperando al cliente", tableName: "Gameflow")
            } icon: {
                Image(systemName: "circle.dashed")
            }
        }
    }
}

#Preview {
    NowView()
}
