import SwiftUI

struct ConnectionMenuSection: View {
    var body: some View {
        Text("Buscando el cliente…", tableName: "Connection")
            .font(.headline)
    }
}

#Preview {
    ConnectionMenuSection()
        .padding()
}
