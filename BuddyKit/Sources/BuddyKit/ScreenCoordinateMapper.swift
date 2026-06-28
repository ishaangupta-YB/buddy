import Foundation

/// Describes a single captured display so coordinates the model returns (in screenshot
/// pixel space, top-left origin) can be mapped onto the physical screen (in AppKit point
/// space, bottom-left origin).
public struct CapturedDisplayGeometry: Equatable, Sendable {
    /// Width of the screenshot image in pixels (the coordinate space the model sees).
    public let screenshotWidthInPixels: Double
    /// Height of the screenshot image in pixels.
    public let screenshotHeightInPixels: Double
    /// Width of the display in AppKit points.
    public let displayWidthInPoints: Double
    /// Height of the display in AppKit points.
    public let displayHeightInPoints: Double
    /// The display's frame in the global AppKit coordinate space (bottom-left origin).
    public let displayFrame: BuddyRect

    public init(
        screenshotWidthInPixels: Double,
        screenshotHeightInPixels: Double,
        displayWidthInPoints: Double,
        displayHeightInPoints: Double,
        displayFrame: BuddyRect
    ) {
        self.screenshotWidthInPixels = screenshotWidthInPixels
        self.screenshotHeightInPixels = screenshotHeightInPixels
        self.displayWidthInPoints = displayWidthInPoints
        self.displayHeightInPoints = displayHeightInPoints
        self.displayFrame = displayFrame
    }
}

/// Converts a pointing coordinate from screenshot pixel space into the global AppKit
/// coordinate the cursor overlay animates to.
///
/// The model is shown each screenshot's pixel dimensions and replies with a coordinate in
/// that space (origin top-left, y increasing downward). The physical display uses AppKit
/// points with the origin at the bottom-left and y increasing upward, and may be a
/// different resolution than the screenshot. This mapper performs the clamp → scale →
/// flip → translate sequence in one pure, testable step.
public enum ScreenCoordinateMapper {
    public static func mapScreenshotPixelToGlobalAppKitPoint(
        screenshotPixelCoordinate: BuddyPoint,
        displayGeometry: CapturedDisplayGeometry
    ) -> BuddyPoint {
        // Clamp into the screenshot's coordinate space so a hallucinated out-of-bounds
        // coordinate never sends the cursor off-screen.
        let clampedHorizontalPixel = max(
            0,
            min(screenshotPixelCoordinate.x, displayGeometry.screenshotWidthInPixels)
        )
        let clampedVerticalPixel = max(
            0,
            min(screenshotPixelCoordinate.y, displayGeometry.screenshotHeightInPixels)
        )

        // Scale from screenshot pixels to display points.
        let horizontalScaleFactor =
            displayGeometry.displayWidthInPoints / displayGeometry.screenshotWidthInPixels
        let verticalScaleFactor =
            displayGeometry.displayHeightInPoints / displayGeometry.screenshotHeightInPixels
        let displayLocalHorizontalPoint = clampedHorizontalPixel * horizontalScaleFactor
        let displayLocalVerticalPointFromTop = clampedVerticalPixel * verticalScaleFactor

        // Flip the vertical axis: screenshots have a top-left origin, AppKit a bottom-left one.
        let displayLocalVerticalPointFromBottom =
            displayGeometry.displayHeightInPoints - displayLocalVerticalPointFromTop

        // Translate display-local points into the global screen coordinate space.
        let globalHorizontalPoint =
            displayLocalHorizontalPoint + displayGeometry.displayFrame.originX
        let globalVerticalPoint =
            displayLocalVerticalPointFromBottom + displayGeometry.displayFrame.originY

        return BuddyPoint(x: globalHorizontalPoint, y: globalVerticalPoint)
    }
}
