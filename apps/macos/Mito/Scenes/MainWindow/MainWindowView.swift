import SwiftUI

struct MainWindowView: View {
    @State private var selection: SidebarDestination? = .now

    var body: some View {
        NavigationSplitView {
            List(SidebarDestination.allCases, id: \.self, selection: $selection) { destination in
                Label {
                    Text(destination.title)
                } icon: {
                    Image(systemName: destination.systemImage)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            if let selection {
                detail(for: selection)
                    .navigationTitle(Text(selection.title))
            }
        }
    }

    @ViewBuilder
    private func detail(for destination: SidebarDestination) -> some View {
        switch destination {
        case .now: NowView()
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
