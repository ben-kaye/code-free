import XCTest
@testable import CodeFree

final class TranscriptReducerTests: XCTestCase {
    func testUserAndErrorProjection() throws {
        let events = [
            event(seq: 1, type: "session.started", payload: ["cwd": .string("/tmp")]),
            event(seq: 2, type: "message.user", payload: ["text": .string("hello"), "id": .string("m1")]),
            event(seq: 3, type: "session.error", payload: [
                "code": .string("no_adapter"),
                "message": .string("No harness adapter configured"),
            ]),
        ]
        let items = TranscriptReducer.reduce(events)
        XCTAssertEqual(items.map(\.kind), [.system, .user, .error])
        XCTAssertEqual(items[1].text, "hello")
        XCTAssertTrue(items[2].text.contains("No harness"))
    }

    func testAssistantDeltaMerge() {
        let events = [
            event(seq: 1, type: "message.delta", payload: ["id": .string("a"), "text": .string("Hel")]),
            event(seq: 2, type: "message.delta", payload: ["id": .string("a"), "text": .string("lo")]),
            event(seq: 3, type: "message.done", payload: ["id": .string("a")]),
        ]
        let items = TranscriptReducer.reduce(events)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].kind, .assistant)
        XCTAssertEqual(items[0].text, "Hello")
    }

    func testLiveApplyAppends() {
        var items: [TranscriptItem] = []
        TranscriptReducer.apply(
            event(seq: 1, type: "message.user", payload: ["text": .string("hi")]),
            to: &items
        )
        TranscriptReducer.apply(
            event(seq: 2, type: "session.error", payload: ["message": .string("err")]),
            to: &items
        )
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].kind, .user)
        XCTAssertEqual(items[1].kind, .error)
    }

    private func event(seq: Int, type: String, payload: [String: JSONValue]) -> EventFrame {
        // Build via JSON round-trip to use Decodable init
        let dict: [String: Any] = [
            "protocolVersion": 1,
            "kind": "event",
            "sessionId": "s1",
            "seq": seq,
            "ts": "2026-01-01T00:00:00.000Z",
            "type": type,
            "payload": payload.mapValues(\.jsonObject),
        ]
        let data = try! JSONSerialization.data(withJSONObject: dict)
        return try! JSONDecoder().decode(EventFrame.self, from: data)
    }
}

private extension JSONValue {
    var jsonObject: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let v): return v
        case .number(let v): return v
        case .string(let v): return v
        case .array(let a): return a.map(\.jsonObject)
        case .object(let o): return o.mapValues(\.jsonObject)
        }
    }
}
