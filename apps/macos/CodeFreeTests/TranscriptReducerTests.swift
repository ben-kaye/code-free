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

    func testToolLifecycleCoalesces() {
        let events = [
            event(seq: 1, type: "tool.started", payload: [
                "name": .string("shell"),
                "summary": .string("ls"),
            ]),
            event(seq: 2, type: "tool.progress", payload: [
                "name": .string("shell"),
                "summary": .string("running"),
            ]),
            event(seq: 3, type: "tool.done", payload: [
                "name": .string("shell"),
                "summary": .string("ok"),
            ]),
        ]
        let items = TranscriptReducer.reduce(events)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].kind, .tool)
        XCTAssertTrue(items[0].text.contains("Done"))
        XCTAssertTrue(items[0].text.contains("shell"))
    }

    func testSecondToolInvocationAppends() {
        let events = [
            event(seq: 1, type: "tool.started", payload: ["name": .string("shell")]),
            event(seq: 2, type: "tool.done", payload: ["name": .string("shell")]),
            event(seq: 3, type: "tool.started", payload: ["name": .string("shell")]),
        ]
        let items = TranscriptReducer.reduce(events)
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items[0].text.contains("Done"))
        XCTAssertTrue(items[1].text.contains("Running"))
    }

    func testToolCoalesceByCallIdNotName() {
        let events = [
            event(seq: 1, type: "tool.started", payload: [
                "id": .string("call_1"),
                "title": .string("Read file"),
            ]),
            event(seq: 2, type: "tool.started", payload: [
                "id": .string("call_2"),
                "title": .string("Read file"),
            ]),
            event(seq: 3, type: "tool.done", payload: [
                "id": .string("call_1"),
            ]),
        ]
        let items = TranscriptReducer.reduce(events)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].messageId, "call_1")
        XCTAssertEqual(items[1].messageId, "call_2")
        XCTAssertTrue(items[0].text.contains("Read file"))
        XCTAssertTrue(items[0].text.contains("Done"))
        XCTAssertTrue(items[1].text.contains("Running"))
    }

    func testToolDoneKeepsTitleFromStart() {
        let events = [
            event(seq: 1, type: "tool.started", payload: [
                "id": .string("c1"),
                "title": .string("Shell"),
                "summary": .string("ls"),
            ]),
            event(seq: 2, type: "tool.done", payload: [
                "id": .string("c1"),
            ]),
        ]
        let items = TranscriptReducer.reduce(events)
        XCTAssertEqual(items.count, 1)
        XCTAssertTrue(items[0].text.hasPrefix("Shell · Done"))
    }

    func testMessageDoneReplacesText() {
        let events = [
            event(seq: 1, type: "message.delta", payload: [
                "id": .string("a"),
                "text": .string("partial"),
            ]),
            event(seq: 2, type: "message.done", payload: [
                "id": .string("a"),
                "text": .string("final answer"),
            ]),
        ]
        let items = TranscriptReducer.reduce(events)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].text, "final answer")
    }

    func testThinkingDeltaMerges() {
        let events = [
            event(seq: 1, type: "thinking.delta", payload: [
                "id": .string("t1"),
                "text": .string("hmm "),
            ]),
            event(seq: 2, type: "thinking.delta", payload: [
                "id": .string("t1"),
                "text": .string("ok"),
            ]),
            event(seq: 3, type: "thinking.done", payload: ["id": .string("t1")]),
        ]
        let items = TranscriptReducer.reduce(events)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].kind, .thinking)
        XCTAssertEqual(items[0].text, "hmm ok")
    }

    func testTurnEndTiming() {
        let items = TranscriptReducer.reduce([
            event(seq: 1, type: "status.turn_end", payload: ["durationMs": .number(1500)]),
        ])
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].kind, .timing)
        XCTAssertTrue(items[0].text.contains("1.5"))
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
