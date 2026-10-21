import SwiftUI

/// The "Mi perfil" destination; the shell builds it without arguments. P8-06 designs it.
struct ProfileView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ProfileScreen(status: app.profile.syncStatus)
    }
}

struct ProfileScreen: View {
    let status: ProfileModel.SyncStatus

    var body: some View {
        ContentUnavailableView {
            Label {
                Text("Sin historial", tableName: "Profile")
            } icon: {
                Image(systemName: "person.crop.circle")
            }
        } description: {
            if let title = status.title {
                HStack(spacing: 6) {
                    if status == .syncing {
                        ProgressView().controlSize(.small)
                    } else if let symbol = status.symbol {
                        Image(systemName: symbol).accessibilityHidden(true)
                    }
                    Text(title)
                }
            }
        }
    }
}

#if DEBUG
    #Preview("Synced") {
        ProfileScreen(status: .synced(newGames: 3))
    }

    #Preview("Syncing") {
        ProfileScreen(status: .syncing)
    }

    #Preview("Failed") {
        ProfileScreen(status: .failed(.client))
    }
#endif
