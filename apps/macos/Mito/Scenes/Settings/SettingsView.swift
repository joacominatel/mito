import SwiftUI

/// The §21.1–21.4 tabs; each tab lives in the feature that owns its settings.
struct SettingsView: View {
    var body: some View {
        TabView {
            OnboardingSettingsTab()
                .tabItem { tabLabel(Text("General", tableName: "Shell"), systemImage: "gearshape") }
            GameflowSettingsTab()
                .tabItem {
                    tabLabel(Text("Partida", tableName: "Shell"), systemImage: "gamecontroller")
                }
            ChampSelectSettingsTab()
                .tabItem {
                    tabLabel(Text("Champ select", tableName: "Shell"), systemImage: "person.3")
                }
            ImportSettingsTab()
                .tabItem {
                    tabLabel(
                        Text("Importación", tableName: "Shell"),
                        systemImage: "square.and.arrow.down")
                }
        }
        .frame(width: 520, height: 360)
    }

    private func tabLabel(_ title: Text, systemImage: String) -> some View {
        Label {
            title
        } icon: {
            Image(systemName: systemImage)
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppModel(connection: DisconnectedLCUConnection()))
}
