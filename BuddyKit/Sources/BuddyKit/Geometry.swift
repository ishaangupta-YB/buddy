import Foundation

/// A simple two-dimensional point used by BuddyKit's pure geometry code.
///
/// BuddyKit deliberately avoids importing CoreGraphics so the core logic stays
/// platform-independent and fully unit-testable on Linux CI. The macOS app converts
/// these values to `CGPoint` at the AppKit boundary.
public struct BuddyPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// A rectangle described by its origin and size, mirroring the fields BuddyKit needs
/// from an AppKit display frame without depending on CoreGraphics.
public struct BuddyRect: Equatable, Sendable {
    public var originX: Double
    public var originY: Double
    public var width: Double
    public var height: Double

    public init(originX: Double, originY: Double, width: Double, height: Double) {
        self.originX = originX
        self.originY = originY
        self.width = width
        self.height = height
    }
}
