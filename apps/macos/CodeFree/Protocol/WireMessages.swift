import Foundation

// Hand Codable mirrors of packages/protocol. Schema is owned by the TS package;
// this layer validates at the shell boundary only.

// MARK: - Shared

struct SessionSummary: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String?
    let cwd: String
    let harnessId: String?
    let model: String?
    let createdAt: String
    let updatedAt: String
    let lastSeq: Int

    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        return "Session \(id.prefix(8))"
    }
}

struct EventFrame: Codable, Hashable, Sendable, Identifiable {
    let protocolVersion: Int
    let kind: String
    let sessionId: String
    let seq: Int
    let ts: String
    let type: String
    let payload: [String: JSONValue]

    var id: Int { seq }

    enum CodingKeys: String, CodingKey {
        case protocolVersion, kind, sessionId, seq, ts, type, payload
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        protocolVersion = try c.decode(Int.self, forKey: .protocolVersion)
        kind = try c.decode(String.self, forKey: .kind)
        sessionId = try c.decode(String.self, forKey: .sessionId)
        seq = try c.decode(Int.self, forKey: .seq)
        ts = try c.decode(String.self, forKey: .ts)
        type = try c.decode(String.self, forKey: .type)
        payload = try c.decodeIfPresent([String: JSONValue].self, forKey: .payload) ?? [:]
    }
}

// MARK: - Client → server

struct ClientHello: Encodable, Sendable {
    let kind: String = "hello"
    let protocolVersion: Int
    let token: String
    let client: ClientInfo?

    struct ClientInfo: Encodable, Sendable {
        let name: String?
        let version: String?
    }
}

struct SessionCreateCommand: Encodable, Sendable {
    let kind: String = "session.create"
    let requestId: String
    let cwd: String
    let title: String?
    let harnessId: String?
    let model: String?
    let seed: String?
}

struct SessionListCommand: Encodable, Sendable {
    let kind: String = "session.list"
    let requestId: String
}

struct SessionSubscribeCommand: Encodable, Sendable {
    let kind: String = "session.subscribe"
    let requestId: String
    let sessionId: String
    let afterSeq: Int?
}

struct SessionUnsubscribeCommand: Encodable, Sendable {
    let kind: String = "session.unsubscribe"
    let requestId: String
    let sessionId: String
}

struct SessionSendCommand: Encodable, Sendable {
    let kind: String = "session.send"
    let requestId: String
    let sessionId: String
    let text: String
}

struct SessionCancelCommand: Encodable, Sendable {
    let kind: String = "session.cancel"
    let requestId: String
    let sessionId: String
}

struct SessionRenameCommand: Encodable, Sendable {
    let kind: String = "session.rename"
    let requestId: String
    let sessionId: String
    let title: String
}

// MARK: - Server → client

struct ServerHello: Decodable, Sendable {
    let kind: String
    let protocolVersion: Int
    let server: ServerInfo?

    struct ServerInfo: Decodable, Sendable {
        let name: String?
        let version: String?
    }
}

struct SnapshotFrame: Decodable, Sendable {
    let kind: String
    let sessionId: String
    let lastSeq: Int
    let events: [EventFrame]
}

struct ErrorFrame: Decodable, Sendable {
    let kind: String
    let code: String
    let message: String
    let sessionId: String?
}

struct CommandResult: Decodable, Sendable {
    let kind: String
    let requestId: String
    let ok: Bool
    let data: JSONValue?
    let error: CommandError?

    struct CommandError: Decodable, Sendable {
        let code: String
        let message: String
    }
}

/// Typed server message after boundary decode.
enum ServerMessage: Sendable {
    case hello(ServerHello)
    case snapshot(SnapshotFrame)
    case event(EventFrame)
    case error(ErrorFrame)
    case result(CommandResult)
}

enum WireDecode {
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    static func serverMessage(from data: Data) throws -> ServerMessage {
        let peek = try decoder.decode(KindPeek.self, from: data)
        switch peek.kind {
        case "hello":
            return .hello(try decoder.decode(ServerHello.self, from: data))
        case "snapshot":
            return .snapshot(try decoder.decode(SnapshotFrame.self, from: data))
        case "event":
            return .event(try decoder.decode(EventFrame.self, from: data))
        case "error":
            return .error(try decoder.decode(ErrorFrame.self, from: data))
        case "result":
            return .result(try decoder.decode(CommandResult.self, from: data))
        default:
            throw WireError.unknownKind(peek.kind)
        }
    }

    private struct KindPeek: Decodable {
        let kind: String
    }
}

enum WireError: Error, LocalizedError {
    case unknownKind(String)
    case encodeFailed
    case unexpectedMessage(String)
    case commandFailed(code: String, message: String)
    case notConnected

    var errorDescription: String? {
        switch self {
        case .unknownKind(let k): return "Unknown wire kind: \(k)"
        case .encodeFailed: return "Failed to encode message"
        case .unexpectedMessage(let m): return "Unexpected message: \(m)"
        case .commandFailed(let code, let message): return "\(code): \(message)"
        case .notConnected: return "Not connected to orchestrator"
        }
    }
}

// MARK: - JSONValue

/// Minimal JSON tree for open payloads (event.payload, result.data).
enum JSONValue: Codable, Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let v = try? c.decode(Bool.self) {
            self = .bool(v)
        } else if let v = try? c.decode(Double.self) {
            self = .number(v)
        } else if let v = try? c.decode(String.self) {
            self = .string(v)
        } else if let v = try? c.decode([JSONValue].self) {
            self = .array(v)
        } else if let v = try? c.decode([String: JSONValue].self) {
            self = .object(v)
        } else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }

    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let o) = self { return o }
        return nil
    }

    var intValue: Int? {
        if case .number(let n) = self { return Int(n) }
        return nil
    }

    subscript(key: String) -> JSONValue? {
        objectValue?[key]
    }
}
