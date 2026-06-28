import SwiftUI

/// The Buddy application entry point.
///
/// Buddy is a menu-bar-only app (`LSUIElement` is true in Info.plist), so there is no
/// `WindowGroup` scene. All lifecycle and UI is driven from `BuddyAppDelegate`, which the
/// SwiftUI `App` adapts via `@NSApplicationDelegateAdaptor`. The single empty `Settings`
/// scene satisfies SwiftUI's requirement for at least one scene without showing a window.
@main
struct BuddyApp: App {
    @NSApplicationDelegateAdaptor(BuddyAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
