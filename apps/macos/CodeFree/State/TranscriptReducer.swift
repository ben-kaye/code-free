import Foundation

/// Transcript item projected from the durable event log. Live stream and replay share this path.
struct TranscriptItem: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case user
        case assistant
        case thinking
        case system
        case error
        case timing
        case tool
        case debug
    }

    let id: String
    let kind: Kind
    let text: String
    let seq: Int
    let messageId: String?
}

enum TranscriptReducer {
    /// Fold a full event list into display items (order preserved).
    static func reduce(_ events: [EventFrame]) -> [TranscriptItem] {
        var items: [TranscriptItem] = []
        // messageId → index in items for streaming deltas
        var assistantIndex: [String: Int] = [:]
        var thinkingIndex: [String: Int] = [:]

        for event in events {
            apply(event, items: &items, assistantIndex: &assistantIndex, thinkingIndex: &thinkingIndex)
        }
        return items
    }

    /// Apply one live event onto an existing transcript.
    static func apply(
        _ event: EventFrame,
        to items: inout [TranscriptItem]
    ) {
        var assistantIndex: [String: Int] = [:]
        var thinkingIndex: [String: Int] = [:]
        for (i, item) in items.enumerated() {
            if item.kind == .assistant, let mid = item.messageId {
                assistantIndex[mid] = i
            }
            if item.kind == .thinking, let mid = item.messageId {
                thinkingIndex[mid] = i
            }
        }
        apply(event, items: &items, assistantIndex: &assistantIndex, thinkingIndex: &thinkingIndex)
    }

    private static func apply(
        _ event: EventFrame,
        items: inout [TranscriptItem],
        assistantIndex: inout [String: Int],
        thinkingIndex: inout [String: Int]
    ) {
        let payload = event.payload
        let messageId = payload["id"]?.stringValue
            ?? payload["messageId"]?.stringValue

        switch event.type {
        case "message.user":
            let text = payload["text"]?.stringValue ?? ""
            items.append(
                TranscriptItem(
                    id: "\(event.seq)-user",
                    kind: .user,
                    text: text,
                    seq: event.seq,
                    messageId: messageId
                )
            )

        case "message.delta":
            let delta = payload["text"]?.stringValue
                ?? payload["delta"]?.stringValue
                ?? ""
            let mid = messageId ?? "assistant-\(event.seq)"
            if let idx = assistantIndex[mid] {
                let prev = items[idx]
                items[idx] = TranscriptItem(
                    id: prev.id,
                    kind: .assistant,
                    text: prev.text + delta,
                    seq: event.seq,
                    messageId: mid
                )
            } else {
                let item = TranscriptItem(
                    id: "\(event.seq)-assistant",
                    kind: .assistant,
                    text: delta,
                    seq: event.seq,
                    messageId: mid
                )
                assistantIndex[mid] = items.count
                items.append(item)
            }

        case "message.done":
            let text = payload["text"]?.stringValue
            let mid = messageId ?? "assistant-\(event.seq)"
            if let text, let idx = assistantIndex[mid] {
                let prev = items[idx]
                items[idx] = TranscriptItem(
                    id: prev.id,
                    kind: .assistant,
                    text: text.isEmpty ? prev.text : text,
                    seq: event.seq,
                    messageId: mid
                )
            } else if let text, !text.isEmpty, assistantIndex[mid] == nil {
                let item = TranscriptItem(
                    id: "\(event.seq)-assistant",
                    kind: .assistant,
                    text: text,
                    seq: event.seq,
                    messageId: mid
                )
                assistantIndex[mid] = items.count
                items.append(item)
            }

        case "thinking.delta":
            let delta = payload["text"]?.stringValue
                ?? payload["delta"]?.stringValue
                ?? ""
            let mid = messageId ?? "thinking-\(event.seq)"
            if let idx = thinkingIndex[mid] {
                let prev = items[idx]
                items[idx] = TranscriptItem(
                    id: prev.id,
                    kind: .thinking,
                    text: prev.text + delta,
                    seq: event.seq,
                    messageId: mid
                )
            } else {
                let item = TranscriptItem(
                    id: "\(event.seq)-thinking",
                    kind: .thinking,
                    text: delta,
                    seq: event.seq,
                    messageId: mid
                )
                thinkingIndex[mid] = items.count
                items.append(item)
            }

        case "thinking.done":
            break

        case "session.started":
            let cwd = payload["cwd"]?.stringValue ?? ""
            items.append(
                TranscriptItem(
                    id: "\(event.seq)-started",
                    kind: .system,
                    text: cwd.isEmpty ? "Session started" : "Session started · \(cwd)",
                    seq: event.seq,
                    messageId: nil
                )
            )

        case "session.ended":
            let reason = payload["reason"]?.stringValue ?? "ended"
            items.append(
                TranscriptItem(
                    id: "\(event.seq)-ended",
                    kind: .system,
                    text: "Session ended (\(reason))",
                    seq: event.seq,
                    messageId: nil
                )
            )

        case "session.error":
            let message = payload["message"]?.stringValue
                ?? payload["code"]?.stringValue
                ?? "Session error"
            items.append(
                TranscriptItem(
                    id: "\(event.seq)-error",
                    kind: .error,
                    text: message,
                    seq: event.seq,
                    messageId: nil
                )
            )

        case "status.turn_end":
            let ms = payload["durationMs"]?.intValue
            let text: String
            if let ms {
                let seconds = Double(ms) / 1000.0
                text = String(format: "Worked for %.1f s", seconds)
            } else {
                text = "Turn complete"
            }
            items.append(
                TranscriptItem(
                    id: "\(event.seq)-timing",
                    kind: .timing,
                    text: text,
                    seq: event.seq,
                    messageId: nil
                )
            )

        case "tool.started", "tool.progress", "tool.done", "tool.error":
            let name = payload["name"]?.stringValue
                ?? payload["tool"]?.stringValue
                ?? "tool"
            let detail = payload["summary"]?.stringValue
                ?? payload["message"]?.stringValue
                ?? event.type
            items.append(
                TranscriptItem(
                    id: "\(event.seq)-tool",
                    kind: .tool,
                    text: "\(name): \(detail)",
                    seq: event.seq,
                    messageId: nil
                )
            )

        case "status", "status.turn_start", "log", "raw":
            break

        default:
            #if DEBUG
            items.append(
                TranscriptItem(
                    id: "\(event.seq)-debug",
                    kind: .debug,
                    text: event.type,
                    seq: event.seq,
                    messageId: nil
                )
            )
            #endif
        }
    }
}
