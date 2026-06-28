import AppKit

/// Owns the top-level objects for the menu-bar app and wires them together at launch.
///
/// The delegate creates the central `CompanionController` (the push-to-talk → screenshot →
/// Workers AI → speech → pointing state machine), the menu bar item and its floating panel,
/// and the always-on cursor overlay window.
@MainActor
final class BuddyAppDelegate: NSObject, NSApplicationDelegate {
    private var companionController: CompanionController?
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The app has no dock icon and no main window — it is an accessory that lives in the
        // status bar. Setting the activation policy explicitly keeps focus from ever moving to a
        // nonexistent window.
        NSApp.setActivationPolicy(.accessory)

        let companionController = CompanionController()
        self.companionController = companionController

        let menuBarController = MenuBarController(companionController: companionController)
        self.menuBarController = menuBarController

        companionController.startListeningForPushToTalk()
    }

    func applicationWillTerminate(_ notification: Notification) {
        companionController?.stopListeningForPushToTalk()
    }
}
