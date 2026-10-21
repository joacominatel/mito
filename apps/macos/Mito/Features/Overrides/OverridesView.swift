import SwiftUI

struct OverridesView: View {
    var body: some View {
        ContentUnavailableView {
            Label {
                Text("Sin overrides", tableName: "Overrides")
            } icon: {
                Image(systemName: "slider.horizontal.3")
            }
        }
    }
}

#Preview {
    OverridesView()
}
