import AppKit

/// Clicking the Dock icon with no window open brings the main window back (§24).
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var reopen: () -> Void = {}

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool)
        -> Bool
    {
        if !flag { Self.reopen() }
        return true
    }
}
