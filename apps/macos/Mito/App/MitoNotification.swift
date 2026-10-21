import Foundation
import MitoCore
import UserNotifications

/// The system notifications of §22.5. Posting lands with each owning feature.
enum MitoNotification: Hashable {
    case matchAccepted
    case pickTurn(recommended: ChampionID?)
    case loadoutImported(champion: ChampionID, opponent: ChampionID?)

    /// One per kind, so a new notification replaces the last one of its kind.
    var identifier: String {
        switch self {
        case .matchAccepted: "matchAccepted"
        case .pickTurn: "pickTurn"
        case .loadoutImported: "loadoutImported"
        }
    }
}

/// `SystemNotificationPoster` in the app; a recorder in tests.
protocol NotificationPosting {
    /// `title` is the owning feature's copy, from its own string table.
    func post(_ notification: MitoNotification, title: LocalizedStringResource) async
}

/// Asks for permission on the first post only; while permission is missing, posts are dropped.
final class SystemNotificationPoster: NotificationPosting {
    private var authorization: Task<Void, Never>?

    func post(_ notification: MitoNotification, title: LocalizedStringResource) async {
        let center = UNUserNotificationCenter.current()
        let authorization =
            self.authorization
            ?? Task { _ = try? await center.requestAuthorization(options: [.alert, .sound]) }
        self.authorization = authorization
        await authorization.value

        let content = UNMutableNotificationContent()
        content.title = String(localized: title)
        let request = UNNotificationRequest(
            identifier: notification.identifier, content: content, trigger: nil)
        // Refused without permission; a grant given later in System Settings applies at once.
        try? await center.add(request)
    }
}
