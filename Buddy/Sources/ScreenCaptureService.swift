import AppKit
import ScreenCaptureKit
import UniformTypeIdentifiers
import BuddyKit

/// The screenshots and per-display geometry captured for a single companion turn.
struct ScreenCaptureResult {
    /// One labeled JPEG per connected display, in the same order as `displayGeometries`.
    let labeledImages: [LabeledScreenImage]
    /// The geometry needed to map a model coordinate back onto each physical display.
    let displayGeometries: [CapturedDisplayGeometry]
}

/// Captures a screenshot of every connected display using ScreenCaptureKit and packages the
/// results for the Workers AI vision request and the cursor-pointing coordinate mapper.
///
/// Each image is labeled with its screen number and pixel dimensions so the model can reason
/// about coordinates, and the display containing the mouse cursor is marked as the
/// "primary focus" so the model knows where the user is working.
@MainActor
final class ScreenCaptureService {
    enum ScreenCaptureError: Error {
        case noDisplaysAvailable
    }

    func captureAllScreens() async throws -> ScreenCaptureResult {
        let shareableContent = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )

        guard !shareableContent.displays.isEmpty else {
            throw ScreenCaptureError.noDisplaysAvailable
        }

        let mouseLocationInGlobalSpace = NSEvent.mouseLocation

        var labeledImages: [LabeledScreenImage] = []
        var displayGeometries: [CapturedDisplayGeometry] = []

        for (displayIndex, display) in shareableContent.displays.enumerated() {
            let screenNumber = displayIndex + 1
            let matchingScreen = matchingNSScreen(for: display)

            let capturedImage = try await captureImage(of: display, within: shareableContent)
            let jpegData = jpegRepresentation(of: capturedImage)

            let screenshotWidthInPixels = Double(capturedImage.width)
            let screenshotHeightInPixels = Double(capturedImage.height)
            let displayFrame = matchingScreen?.frame
                ?? NSRect(x: 0, y: 0, width: CGFloat(display.width), height: CGFloat(display.height))

            let isPrimaryFocusDisplay = matchingScreen.map { screen in
                NSPointInRect(mouseLocationInGlobalSpace, screen.frame)
            } ?? (displayIndex == 0)

            let label = makeLabel(
                screenNumber: screenNumber,
                screenshotWidthInPixels: screenshotWidthInPixels,
                screenshotHeightInPixels: screenshotHeightInPixels,
                isPrimaryFocusDisplay: isPrimaryFocusDisplay
            )

            labeledImages.append(LabeledScreenImage(imageData: jpegData, label: label))
            displayGeometries.append(
                CapturedDisplayGeometry(
                    screenshotWidthInPixels: screenshotWidthInPixels,
                    screenshotHeightInPixels: screenshotHeightInPixels,
                    displayWidthInPoints: Double(displayFrame.width),
                    displayHeightInPoints: Double(displayFrame.height),
                    displayFrame: BuddyRect(
                        originX: Double(displayFrame.origin.x),
                        originY: Double(displayFrame.origin.y),
                        width: Double(displayFrame.width),
                        height: Double(displayFrame.height)
                    )
                )
            )
        }

        return ScreenCaptureResult(labeledImages: labeledImages, displayGeometries: displayGeometries)
    }

    private func captureImage(
        of display: SCDisplay,
        within shareableContent: SCShareableContent
    ) async throws -> CGImage {
        let contentFilter = SCContentFilter(display: display, excludingWindows: [])

        let streamConfiguration = SCStreamConfiguration()
        streamConfiguration.width = display.width
        streamConfiguration.height = display.height
        streamConfiguration.showsCursor = true
        streamConfiguration.captureResolution = .best

        return try await SCScreenshotManager.captureImage(
            contentFilter: contentFilter,
            configuration: streamConfiguration
        )
    }

    private func matchingNSScreen(for display: SCDisplay) -> NSScreen? {
        NSScreen.screens.first { screen in
            let screenNumberValue = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber
            return screenNumberValue?.uint32Value == display.displayID
        }
    }

    private func jpegRepresentation(of cgImage: CGImage) -> Data {
        let bitmapRepresentation = NSBitmapImageRep(cgImage: cgImage)
        let jpegData = bitmapRepresentation.representation(
            using: .jpeg,
            properties: [.compressionFactor: 0.7]
        )
        return jpegData ?? Data()
    }

    private func makeLabel(
        screenNumber: Int,
        screenshotWidthInPixels: Double,
        screenshotHeightInPixels: Double,
        isPrimaryFocusDisplay: Bool
    ) -> String {
        let widthPixels = Int(screenshotWidthInPixels)
        let heightPixels = Int(screenshotHeightInPixels)
        let focusSuffix = isPrimaryFocusDisplay ? " (primary focus — the cursor is here)" : ""
        return "screen\(screenNumber)\(focusSuffix): image dimensions \(widthPixels)x\(heightPixels) pixels"
    }
}
