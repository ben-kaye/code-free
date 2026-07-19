import XCTest
@testable import CodeFree

final class UserBannerTests: XCTestCase {
    func testSessionNotFoundIsHumanAndRecoverable() {
        let banner = UserBanner.from(code: "session_not_found", message: "Session not found")
        XCTAssertEqual(banner.message, "That task is no longer available")
        XCTAssertEqual(banner.style, .warning)
        XCTAssertEqual(banner.action, .newTask)
        XCTAssertFalse(banner.message.contains("session_not_found"))
    }

    func testWireErrorMapsThroughFromError() {
        let error = WireError.commandFailed(code: "session_not_found", message: "Session not found")
        let banner = UserBanner.from(error: error)
        XCTAssertEqual(banner.message, "That task is no longer available")
        XCTAssertEqual(banner.action, .newTask)
    }

    func testConnectionLossSuggestsRestart() {
        let banner = UserBanner.from(error: WireError.notConnected)
        XCTAssertEqual(banner.action, .restart)
        XCTAssertEqual(banner.style, .error)
    }

    func testUnknownCodeUsesServerMessageWithoutCodePrefix() {
        let banner = UserBanner.from(code: "weird_error", message: "Something readable")
        XCTAssertEqual(banner.message, "Something readable")
        XCTAssertFalse(banner.message.contains("weird_error"))
    }
}
