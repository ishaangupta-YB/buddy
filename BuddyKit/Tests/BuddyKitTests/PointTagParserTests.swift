import XCTest
@testable import BuddyKit

final class PointTagParserTests: XCTestCase {
    func testParsesCoordinateWithLabel() {
        let result = PointTagParser.parse(
            from: "open the color inspector up top. [POINT:1100,42:color inspector]"
        )
        XCTAssertEqual(result.spokenText, "open the color inspector up top.")
        XCTAssertEqual(result.coordinate, BuddyPoint(x: 1100, y: 42))
        XCTAssertEqual(result.elementLabel, "color inspector")
        XCTAssertNil(result.screenNumber)
    }

    func testParsesCoordinateWithLabelAndScreenNumber() {
        let result = PointTagParser.parse(
            from: "that's on your other monitor. [POINT:400,300:terminal:screen2]"
        )
        XCTAssertEqual(result.spokenText, "that's on your other monitor.")
        XCTAssertEqual(result.coordinate, BuddyPoint(x: 400, y: 300))
        XCTAssertEqual(result.elementLabel, "terminal")
        XCTAssertEqual(result.screenNumber, 2)
    }

    func testParsesNoneTag() {
        let result = PointTagParser.parse(from: "html is the skeleton of a web page. [POINT:none]")
        XCTAssertEqual(result.spokenText, "html is the skeleton of a web page.")
        XCTAssertNil(result.coordinate)
        XCTAssertEqual(result.elementLabel, "none")
        XCTAssertNil(result.screenNumber)
    }

    func testCoordinateWithoutLabelStillParses() {
        let result = PointTagParser.parse(from: "right there. [POINT:10,20]")
        XCTAssertEqual(result.spokenText, "right there.")
        XCTAssertEqual(result.coordinate, BuddyPoint(x: 10, y: 20))
        XCTAssertNil(result.elementLabel)
    }

    func testNoTagReturnsWholeTextAsSpoken() {
        let result = PointTagParser.parse(from: "just a plain answer with no tag")
        XCTAssertEqual(result.spokenText, "just a plain answer with no tag")
        XCTAssertNil(result.coordinate)
        XCTAssertNil(result.elementLabel)
        XCTAssertNil(result.screenNumber)
    }

    func testOnlyMatchesTagAtEnd() {
        // A bracketed phrase mid-sentence that is not a trailing POINT tag is left intact.
        let result = PointTagParser.parse(from: "the array is [1,2,3] in your code")
        XCTAssertEqual(result.spokenText, "the array is [1,2,3] in your code")
        XCTAssertNil(result.coordinate)
    }
}
