import XCTest
@testable import BuddyKit

final class ChatStreamDecoderTests: XCTestCase {
    private let decoder = ChatStreamDecoder()

    func testDecodesContentDelta() {
        let chunk = decoder.decodeTextChunk(
            fromServerSentEventLine: "data: {\"choices\":[{\"delta\":{\"content\":\"hi\"}}]}"
        )
        XCTAssertEqual(chunk, "hi")
    }

    func testIgnoresDoneMarkerAndNonDataLines() {
        XCTAssertNil(decoder.decodeTextChunk(fromServerSentEventLine: "data: [DONE]"))
        XCTAssertNil(decoder.decodeTextChunk(fromServerSentEventLine: ": keep-alive comment"))
        XCTAssertNil(decoder.decodeTextChunk(fromServerSentEventLine: ""))
        XCTAssertTrue(decoder.isStreamDoneMarker("data: [DONE]"))
        XCTAssertFalse(decoder.isStreamDoneMarker("data: {\"choices\":[]}"))
    }

    func testIgnoresEmptyContentDelta() {
        XCTAssertNil(
            decoder.decodeTextChunk(
                fromServerSentEventLine: "data: {\"choices\":[{\"delta\":{\"role\":\"assistant\"}}]}"
            )
        )
    }
}

final class ScreenCoordinateMapperTests: XCTestCase {
    func testMapsScreenshotPixelToGlobalAppKitPointWithScalingAndFlip() {
        // Screenshot is 1280x800; display is 640x400 points at the global origin.
        let geometry = CapturedDisplayGeometry(
            screenshotWidthInPixels: 1280,
            screenshotHeightInPixels: 800,
            displayWidthInPoints: 640,
            displayHeightInPoints: 400,
            displayFrame: BuddyRect(originX: 0, originY: 0, width: 640, height: 400)
        )
        // Pixel (640, 400) is the screenshot center -> display point (320, 200 from top),
        // flipped to (320, 200) from the bottom.
        let mapped = ScreenCoordinateMapper.mapScreenshotPixelToGlobalAppKitPoint(
            screenshotPixelCoordinate: BuddyPoint(x: 640, y: 400),
            displayGeometry: geometry
        )
        XCTAssertEqual(mapped, BuddyPoint(x: 320, y: 200))
    }

    func testTopLeftPixelMapsToTopLeftAppKitPointOnOffsetDisplay() {
        // A secondary display offset to the right at x=1000.
        let geometry = CapturedDisplayGeometry(
            screenshotWidthInPixels: 1000,
            screenshotHeightInPixels: 500,
            displayWidthInPoints: 1000,
            displayHeightInPoints: 500,
            displayFrame: BuddyRect(originX: 1000, originY: 0, width: 1000, height: 500)
        )
        // Screenshot top-left (0,0) -> AppKit top-left = bottom-flip y=500, plus x offset.
        let mapped = ScreenCoordinateMapper.mapScreenshotPixelToGlobalAppKitPoint(
            screenshotPixelCoordinate: BuddyPoint(x: 0, y: 0),
            displayGeometry: geometry
        )
        XCTAssertEqual(mapped, BuddyPoint(x: 1000, y: 500))
    }

    func testClampsOutOfBoundsCoordinate() {
        let geometry = CapturedDisplayGeometry(
            screenshotWidthInPixels: 100,
            screenshotHeightInPixels: 100,
            displayWidthInPoints: 100,
            displayHeightInPoints: 100,
            displayFrame: BuddyRect(originX: 0, originY: 0, width: 100, height: 100)
        )
        let mapped = ScreenCoordinateMapper.mapScreenshotPixelToGlobalAppKitPoint(
            screenshotPixelCoordinate: BuddyPoint(x: 9999, y: -50),
            displayGeometry: geometry
        )
        // x clamps to 100 -> point 100; y clamps to 0 (top) -> flipped to 100.
        XCTAssertEqual(mapped, BuddyPoint(x: 100, y: 100))
    }
}

final class ConversationHistoryStoreTests: XCTestCase {
    func testTrimsOldestBeyondLimit() {
        var store = ConversationHistoryStore(limit: 2)
        store.record(userText: "a", assistantText: "1")
        store.record(userText: "b", assistantText: "2")
        store.record(userText: "c", assistantText: "3")
        XCTAssertEqual(store.exchanges.count, 2)
        XCTAssertEqual(store.exchanges.first?.userText, "b")
        XCTAssertEqual(store.exchanges.last?.userText, "c")
    }

    func testResetClearsHistory() {
        var store = ConversationHistoryStore(limit: 5)
        store.record(userText: "a", assistantText: "1")
        store.reset()
        XCTAssertTrue(store.exchanges.isEmpty)
    }

    func testNonPositiveLimitIsClampedToOne() {
        var store = ConversationHistoryStore(limit: 0)
        store.record(userText: "a", assistantText: "1")
        store.record(userText: "b", assistantText: "2")
        XCTAssertEqual(store.exchanges.count, 1)
        XCTAssertEqual(store.exchanges.first?.userText, "b")
    }
}

final class LabeledScreenImageTests: XCTestCase {
    func testDetectsPNGFromMagicBytes() {
        let pngBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let image = LabeledScreenImage(imageData: pngBytes, label: "x")
        XCTAssertEqual(image.detectedMimeType(), "image/png")
        XCTAssertTrue(image.base64DataURI().hasPrefix("data:image/png;base64,"))
    }

    func testDefaultsToJPEG() {
        let jpegBytes = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let image = LabeledScreenImage(imageData: jpegBytes, label: "x")
        XCTAssertEqual(image.detectedMimeType(), "image/jpeg")
    }
}
