import AppKit
import SwiftUI

/// Creates the menu bar status item and manages the floating control panel that appears when
/// the user clicks it.
///
/// A custom borderless, non-activating `NSPanel` is used instead of a standard menu or popover
/// so the panel can have Buddy's rounded, dark appearance and never steals focus from the
/// user's frontmost app. A global click monitor dismisses the panel when the user clicks away.
@MainActor
final class MenuBarController {
    private let companionController: CompanionController
    private let statusItem: NSStatusItem
    private var controlPanel: NSPanel?
    private var clickOutsideMonitor: Any?

    init(companionController: CompanionController) {
        self.companionController = companionController
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureStatusItemButton()
    }

    private func configureStatusItemButton() {
        guard let statusButton = statusItem.button else { return }
        statusButton.image = NSImage(
            systemSymbolName: "sparkles",
            accessibilityDescription: "Buddy"
        )
        statusButton.image?.isTemplate = true
        statusButton.target = self
        statusButton.action = #selector(handleStatusItemClicked)
    }

    @objc private func handleStatusItemClicked() {
        if controlPanel?.isVisible == true {
            dismissControlPanel()
        } else {
            presentControlPanel()
        }
    }

    private func presentControlPanel() {
        let controlPanel = controlPanel ?? buildControlPanel()
        self.controlPanel = controlPanel

        positionControlPanelBelowStatusItem(controlPanel)
        controlPanel.orderFrontRegardless()
        installClickOutsideMonitor()
    }

    private func dismissControlPanel() {
        controlPanel?.orderOut(nil)
        removeClickOutsideMonitor()
    }

    private func buildControlPanel() -> NSPanel {
        let panelContentView = CompanionPanelView(
            companionController: companionController,
            onQuitRequested: { NSApp.terminate(nil) }
        )

        let hostingView = NSHostingView(rootView: panelContentView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 320, height: 360)

        let controlPanel = NSPanel(
            contentRect: hostingView.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        controlPanel.isOpaque = false
        controlPanel.backgroundColor = .clear
        controlPanel.hasShadow = true
        controlPanel.level = .floating
        controlPanel.collectionBehavior = [.canJoinAllSpaces, .moveToActiveSpace]
        controlPanel.contentView = hostingView
        return controlPanel
    }

    private func positionControlPanelBelowStatusItem(_ controlPanel: NSPanel) {
        guard
            let statusButton = statusItem.button,
            let buttonWindow = statusButton.window
        else { return }

        let buttonFrameInScreen = buttonWindow.convertToScreen(statusButton.frame)
        let panelSize = controlPanel.frame.size
        let panelOriginX = buttonFrameInScreen.midX - (panelSize.width / 2)
        let panelOriginY = buttonFrameInScreen.minY - panelSize.height - 6
        controlPanel.setFrameOrigin(NSPoint(x: panelOriginX, y: panelOriginY))
    }

    private func installClickOutsideMonitor() {
        removeClickOutsideMonitor()
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                self?.dismissControlPanel()
            }
        }
    }

    private func removeClickOutsideMonitor() {
        if let clickOutsideMonitor {
            NSEvent.removeMonitor(clickOutsideMonitor)
        }
        clickOutsideMonitor = nil
    }
}
