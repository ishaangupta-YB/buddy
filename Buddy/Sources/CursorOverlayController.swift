import AppKit
import SwiftUI

/// The observable model the overlay SwiftUI view renders. The controller mutates these
/// published values; SwiftUI animates the cursor and response bubble in response.
@MainActor
final class CursorOverlayModel: ObservableObject {
    @Published var isVisible: Bool = false
    @Published var responseText: String = ""
    @Published var elementLabel: String?
    @Published var isPointing: Bool = false

    /// The cursor's position in the overlay view's coordinate space (top-left origin).
    @Published var cursorPositionInOverlay: CGPoint = .zero
}

/// Owns the full-screen transparent overlay panel that hosts Buddy's cursor companion and
/// response bubble, and exposes a small command surface the `CompanionController` drives.
///
/// The panel is a non-activating, borderless `NSPanel` that joins every Space and floats above
/// normal windows without ever stealing focus, so the user keeps working while Buddy points.
@MainActor
final class CursorOverlayController {
    private let overlayModel = CursorOverlayModel()
    private var overlayPanel: NSPanel?
    private var fadeOutWorkItem: DispatchWorkItem?

    init() {
        buildOverlayPanelIfNeeded()
    }

    // MARK: - Commands from the companion controller

    func showListeningState() {
        cancelScheduledFadeOut()
        overlayModel.responseText = ""
        overlayModel.isPointing = false
        overlayModel.elementLabel = nil
        positionCursorAtScreenCenter()
        setVisible(true)
    }

    func showProcessingState() {
        cancelScheduledFadeOut()
        setVisible(true)
    }

    func updateResponseText(_ responseText: String) {
        cancelScheduledFadeOut()
        overlayModel.responseText = responseText
        setVisible(true)
    }

    func pointCursor(atGlobalPoint globalPoint: CGPoint, elementLabel: String?) {
        cancelScheduledFadeOut()
        setVisible(true)
        overlayModel.elementLabel = elementLabel
        overlayModel.isPointing = true

        let overlayPosition = convertGlobalPointToOverlayPosition(globalPoint)
        withAnimation(.easeInOut(duration: 0.7)) {
            overlayModel.cursorPositionInOverlay = overlayPosition
        }
    }

    /// Fades the overlay out shortly after a turn ends so it does not linger on screen.
    func scheduleFadeOutAfterInteraction() {
        cancelScheduledFadeOut()
        let fadeOutWorkItem = DispatchWorkItem { [weak self] in
            self?.setVisible(false)
            self?.overlayModel.isPointing = false
        }
        self.fadeOutWorkItem = fadeOutWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0, execute: fadeOutWorkItem)
    }

    // MARK: - Panel construction

    private func buildOverlayPanelIfNeeded() {
        guard overlayPanel == nil else { return }

        let overlayFrame = unionFrameOfAllScreens()
        let overlayPanel = NSPanel(
            contentRect: overlayFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        overlayPanel.isOpaque = false
        overlayPanel.backgroundColor = .clear
        overlayPanel.hasShadow = false
        overlayPanel.level = .screenSaver
        overlayPanel.ignoresMouseEvents = true
        overlayPanel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        overlayPanel.hidesOnDeactivate = false

        let hostingView = NSHostingView(
            rootView: CursorOverlayView(overlayModel: overlayModel)
        )
        hostingView.frame = NSRect(origin: .zero, size: overlayFrame.size)
        overlayPanel.contentView = hostingView

        self.overlayPanel = overlayPanel
    }

    private func setVisible(_ isVisible: Bool) {
        overlayModel.isVisible = isVisible
        guard let overlayPanel else { return }
        if isVisible {
            overlayPanel.orderFrontRegardless()
        } else {
            overlayPanel.orderOut(nil)
        }
    }

    // MARK: - Coordinate conversion

    /// Converts a global AppKit point (bottom-left origin) to the overlay view's coordinate
    /// space (top-left origin, relative to the union frame of all screens).
    private func convertGlobalPointToOverlayPosition(_ globalPoint: CGPoint) -> CGPoint {
        let overlayFrame = unionFrameOfAllScreens()
        let overlayLocalX = globalPoint.x - overlayFrame.origin.x
        let overlayLocalYFromBottom = globalPoint.y - overlayFrame.origin.y
        let overlayLocalYFromTop = overlayFrame.height - overlayLocalYFromBottom
        return CGPoint(x: overlayLocalX, y: overlayLocalYFromTop)
    }

    private func positionCursorAtScreenCenter() {
        let overlayFrame = unionFrameOfAllScreens()
        overlayModel.cursorPositionInOverlay = CGPoint(
            x: overlayFrame.width / 2,
            y: overlayFrame.height / 2
        )
    }

    private func unionFrameOfAllScreens() -> NSRect {
        NSScreen.screens.reduce(NSRect.zero) { accumulatedFrame, screen in
            accumulatedFrame.isEmpty ? screen.frame : accumulatedFrame.union(screen.frame)
        }
    }

    private func cancelScheduledFadeOut() {
        fadeOutWorkItem?.cancel()
        fadeOutWorkItem = nil
    }
}
