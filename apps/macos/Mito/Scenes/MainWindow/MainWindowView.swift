import SwiftUI

struct MainWindowView: View {
    var body: some View {
        NavigationSplitView {
            List {
                Label("Ahora", systemImage: "bolt")
                Label("Campeones", systemImage: "person.3")
                Label("Mi perfil", systemImage: "person.crop.circle")
                Label("Overrides", systemImage: "slider.horizontal.3")
            }
        } detail: {
            ContentUnavailableView("Esperando al cliente", systemImage: "circle.dashed")
        }
    }
}
