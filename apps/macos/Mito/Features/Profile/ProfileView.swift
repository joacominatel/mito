import SwiftUI

struct ProfileView: View {
    var body: some View {
        ContentUnavailableView {
            Label {
                Text("Sin historial", tableName: "Profile")
            } icon: {
                Image(systemName: "person.crop.circle")
            }
        }
    }
}

#Preview {
    ProfileView()
}
