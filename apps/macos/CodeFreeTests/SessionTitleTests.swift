import XCTest
@testable import CodeFree

final class SessionTitleTests: XCTestCase {
    func testShortMessageUnchanged() {
        XCTAssertEqual(SessionSummary.titleFromMessage("Fix the bug"), "Fix the bug")
    }

    func testUsesFirstLineOnly() {
        let text = "First line is the title\nSecond line is details"
        XCTAssertEqual(SessionSummary.titleFromMessage(text), "First line is the title")
    }

    func testWordBoundaryTruncation() {
        let text = "Please implement the authentication flow carefully for production"
        let title = SessionSummary.titleFromMessage(text, maxLength: 40)
        XCTAssertTrue(title.hasSuffix("…"))
        XCTAssertFalse(title.contains("authentica…") || title.hasSuffix("a…"))
        // Should not cut mid-word when a space exists in the prefix
        let withoutEllipsis = String(title.dropLast())
        XCTAssertFalse(withoutEllipsis.hasSuffix(" "))
        XCTAssertTrue(withoutEllipsis.split(separator: " ").count >= 2)
    }

    func testEmptyBecomesUntitled() {
        XCTAssertEqual(SessionSummary.titleFromMessage("   "), "Untitled task")
    }
}
