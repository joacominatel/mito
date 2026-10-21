import SwiftUI

struct MainWindowView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var window = app.mainWindow
        NavigationSplitView {
            List(SidebarDestination.allCases, id: \.self, selection: $window.destination) {
                destination in
                Label {
                    Text(destination.title)
                } icon: {
                    Image(systemName: destination.systemImage)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            if let destination = window.destination {
                detail(for: destination)
                    .navigationTitle(Text(destination.title))
                    .navigationBarGlass()
            }
        }
        .importToast()
        .onAppear { app.presence.windowOpened(.main) }
        .onDisappear { app.presence.windowClosed(.main) }
    }

    @ViewBuilder
    private func detail(for destination: SidebarDestination) -> some View {
        switch destination {
        case .now:
            NowView(
                champSelect: app.champSelect.isInChampSelect
                    ? ChampSelectView(model: app.champSelect) : nil)
        case .champions: ChampionsView()
        case .profile: ProfileView()
        case .overrides: OverridesView()
        }
    }
}

#Preview {
    MainWindowView()
        .environment(AppModel(connection: DisconnectedLCUConnection()))
}
