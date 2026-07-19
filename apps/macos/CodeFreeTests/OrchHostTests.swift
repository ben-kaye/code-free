import XCTest
@testable import CodeFree

final class OrchHostTests: XCTestCase {
    func testProcessAliveRejectsInvalidPid() {
        XCTAssertFalse(OrchHost.isProcessAlive(0))
        XCTAssertFalse(OrchHost.isProcessAlive(-1))
    }

    func testProcessAliveSelf() {
        let pid = ProcessInfo.processInfo.processIdentifier
        XCTAssertTrue(OrchHost.isProcessAlive(pid))
    }

    func testEndpointReachableRejectsBadURL() {
        XCTAssertFalse(OrchHost.isEndpointReachable(URL(string: "ws://not-a-host")!))
        // Closed high port on loopback should fail quickly.
        XCTAssertFalse(
            OrchHost.isEndpointReachable(URL(string: "ws://127.0.0.1:1")!, timeout: 0.2)
        )
    }
}
