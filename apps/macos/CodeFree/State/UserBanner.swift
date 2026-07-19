import Foundation

/// User-facing shell banner. Protocol codes map here — never show raw wire language.
struct UserBanner: Equatable {
    enum Style: Equatable {
        case info
        case warning
        case error
    }

    enum Action: Equatable {
        case newTask
        case restart
    }

    var message: String
    var style: Style
    var action: Action?

    var actionLabel: String? {
        switch action {
        case .newTask: return "New task"
        case .restart: return "Restart"
        case nil: return nil
        }
    }

    static func info(_ message: String, action: Action? = nil) -> UserBanner {
        UserBanner(message: message, style: .info, action: action)
    }

    static func warning(_ message: String, action: Action? = nil) -> UserBanner {
        UserBanner(message: message, style: .warning, action: action)
    }

    static func error(_ message: String, action: Action? = nil) -> UserBanner {
        UserBanner(message: message, style: .error, action: action)
    }

    /// Map a thrown error (including `WireError.commandFailed`) to plain copy.
    static func from(error: Error) -> UserBanner {
        if let wire = error as? WireError {
            switch wire {
            case .commandFailed(let code, let message):
                return from(code: code, message: message)
            case .notConnected:
                return .error("Not connected to the orchestrator", action: .restart)
            case .unexpectedMessage(let m) where m.contains("timeout"):
                return .error("The orchestrator timed out. Try again.")
            case .unexpectedMessage, .unknownKind, .encodeFailed:
                return .error(wire.localizedDescription)
            }
        }
        return .error(error.localizedDescription)
    }

    /// Map protocol / command error codes to product copy + recovery.
    static func from(code: String, message: String) -> UserBanner {
        switch code {
        case "session_not_found":
            return .warning("That task is no longer available", action: .newTask)
        case "auth_failed", "invalid_hello":
            return .error("Could not authenticate with the orchestrator", action: .restart)
        case "not_connected":
            return .error("Not connected to the orchestrator", action: .restart)
        case "protocol_mismatch":
            return .error("Incompatible orchestrator version", action: .restart)
        default:
            // Prefer the server message when it is already readable; never prefix with code.
            let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                return .error("Something went wrong")
            }
            return .error(text)
        }
    }
}
