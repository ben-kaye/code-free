import Foundation

/// WebSocket client for the Code Free orchestrator. Protocol-only; no harness knowledge.
actor OrchClient {
    enum ConnectionState: Equatable, Sendable {
        case disconnected
        case connecting
        case authenticating
        case connected
        case failed(String)
    }

    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var receiveLoop: Task<Void, Never>?
    private var pending: [String: CheckedContinuation<CommandResult, Error>] = [:]
    private var state: ConnectionState = .disconnected
    private var onState: (@Sendable (ConnectionState) -> Void)?
    private var onEvent: (@Sendable (EventFrame) -> Void)?
    private var onSnapshot: (@Sendable (SnapshotFrame) -> Void)?
    private var onServerError: (@Sendable (ErrorFrame) -> Void)?

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func setHandlers(
        onState: @escaping @Sendable (ConnectionState) -> Void,
        onEvent: @escaping @Sendable (EventFrame) -> Void,
        onSnapshot: @escaping @Sendable (SnapshotFrame) -> Void,
        onServerError: @escaping @Sendable (ErrorFrame) -> Void
    ) {
        self.onState = onState
        self.onEvent = onEvent
        self.onSnapshot = onSnapshot
        self.onServerError = onServerError
    }

    func connect(endpoint: URL, token: String) async throws {
        await disconnect(notify: false)
        setState(.connecting)

        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = false
        let urlSession = URLSession(configuration: config)
        self.session = urlSession

        let ws = urlSession.webSocketTask(with: endpoint)
        self.task = ws
        ws.resume()

        setState(.authenticating)
        startReceiveLoop()

        let hello = ClientHello(
            protocolVersion: ProtocolVersion.current,
            token: token,
            client: .init(name: "code-free-macos", version: "0.1.0")
        )
        try await sendEncodable(hello)

        // Wait for server hello via first matching message handled in receive loop is racy;
        // instead block briefly by using a one-shot continuation for hello.
        // Receive loop routes hello by completing helloWait.
        try await waitForHello()
        setState(.connected)
    }

    private var helloContinuation: CheckedContinuation<Void, Error>?

    private func waitForHello() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.helloContinuation = cont
            // Timeout if server never greets
            Task {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if let c = self.helloContinuation {
                    self.helloContinuation = nil
                    c.resume(throwing: WireError.unexpectedMessage("hello timeout"))
                }
            }
        }
    }

    func disconnect(notify: Bool = true) async {
        receiveLoop?.cancel()
        receiveLoop = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
        for (_, cont) in pending {
            cont.resume(throwing: WireError.notConnected)
        }
        pending.removeAll()
        if let c = helloContinuation {
            helloContinuation = nil
            c.resume(throwing: WireError.notConnected)
        }
        if notify {
            setState(.disconnected)
        }
    }

    // MARK: - Commands

    func listSessions(filter: String = "active") async throws -> [SessionSummary] {
        let result = try await request(SessionListCommand(requestId: newId(), filter: filter))
        return try decodeSessions(result)
    }

    func archiveSession(sessionId: String) async throws -> SessionSummary {
        let result = try await request(
            SessionArchiveCommand(requestId: newId(), sessionId: sessionId)
        )
        guard let data = result.data?.objectValue,
              let sessionVal = data["session"]
        else {
            throw WireError.unexpectedMessage("session.archive missing session")
        }
        return try decodeValue(SessionSummary.self, from: sessionVal)
    }

    func createSession(
        cwd: String,
        title: String? = nil,
        harnessId: String? = nil,
        model: String? = nil
    ) async throws -> SessionSummary {
        let result = try await request(
            SessionCreateCommand(
                requestId: newId(),
                cwd: cwd,
                title: title,
                harnessId: harnessId,
                model: model,
                seed: nil
            )
        )
        guard let data = result.data?.objectValue,
              let sessionVal = data["session"]
        else {
            throw WireError.unexpectedMessage("session.create missing session")
        }
        return try decodeValue(SessionSummary.self, from: sessionVal)
    }

    func listHarnesses() async throws -> [HarnessInfo] {
        let result = try await request(HarnessListCommand(requestId: newId()))
        guard let data = result.data?.objectValue,
              case .array(let arr) = data["harnesses"]
        else {
            return []
        }
        return try arr.map { try decodeValue(HarnessInfo.self, from: $0) }
    }

    func subscribe(sessionId: String, afterSeq: Int = 0) async throws {
        _ = try await request(
            SessionSubscribeCommand(
                requestId: newId(),
                sessionId: sessionId,
                afterSeq: afterSeq
            )
        )
    }

    func unsubscribe(sessionId: String) async throws {
        _ = try await request(
            SessionUnsubscribeCommand(requestId: newId(), sessionId: sessionId)
        )
    }

    func send(sessionId: String, text: String) async throws {
        _ = try await request(
            SessionSendCommand(requestId: newId(), sessionId: sessionId, text: text)
        )
    }

    func cancel(sessionId: String) async throws {
        _ = try await request(
            SessionCancelCommand(requestId: newId(), sessionId: sessionId)
        )
    }

    func rename(sessionId: String, title: String) async throws -> SessionSummary {
        let result = try await request(
            SessionRenameCommand(requestId: newId(), sessionId: sessionId, title: title)
        )
        guard let data = result.data?.objectValue,
              let sessionVal = data["session"]
        else {
            throw WireError.unexpectedMessage("session.rename missing session")
        }
        return try decodeValue(SessionSummary.self, from: sessionVal)
    }

    // MARK: - Internals

    private func request<T: Encodable>(_ body: T) async throws -> CommandResult {
        guard task != nil, case .connected = state else {
            throw WireError.notConnected
        }
        let data = try encoder.encode(body)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let requestId = obj["requestId"] as? String
        else {
            throw WireError.encodeFailed
        }

        return try await withCheckedThrowingContinuation { cont in
            pending[requestId] = cont
            Task {
                do {
                    try await sendData(data)
                } catch {
                    if let c = self.pending.removeValue(forKey: requestId) {
                        c.resume(throwing: error)
                    }
                }
            }
            // Timeout pending RPCs
            Task {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                if let c = self.pending.removeValue(forKey: requestId) {
                    c.resume(throwing: WireError.unexpectedMessage("request timeout: \(requestId)"))
                }
            }
        }
    }

    private func sendEncodable<T: Encodable>(_ value: T) async throws {
        let data = try encoder.encode(value)
        try await sendData(data)
    }

    private func sendData(_ data: Data) async throws {
        guard let task else { throw WireError.notConnected }
        guard let text = String(data: data, encoding: .utf8) else {
            throw WireError.encodeFailed
        }
        try await task.send(.string(text))
    }

    private func startReceiveLoop() {
        receiveLoop?.cancel()
        receiveLoop = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    guard let task = await self.currentTask() else { break }
                    let message = try await task.receive()
                    try await self.handle(message)
                } catch {
                    if Task.isCancelled { break }
                    await self.handleReceiveFailure(error)
                    break
                }
            }
        }
    }

    private func currentTask() -> URLSessionWebSocketTask? { task }

    private func handle(_ message: URLSessionWebSocketTask.Message) async throws {
        let data: Data
        switch message {
        case .string(let text):
            guard let d = text.data(using: .utf8) else { return }
            data = d
        case .data(let d):
            data = d
        @unknown default:
            return
        }

        let msg: ServerMessage
        do {
            msg = try WireDecode.serverMessage(from: data)
        } catch {
            setState(.failed("Invalid frame from orchestrator"))
            return
        }

        switch msg {
        case .hello:
            if let c = helloContinuation {
                helloContinuation = nil
                c.resume()
            }
        case .snapshot(let snap):
            onSnapshot?(snap)
        case .event(let ev):
            onEvent?(ev)
        case .error(let err):
            onServerError?(err)
            if err.code == "auth_failed" || err.code == "invalid_hello" {
                if let c = helloContinuation {
                    helloContinuation = nil
                    c.resume(throwing: WireError.commandFailed(code: err.code, message: err.message))
                }
                setState(.failed(err.message))
            }
        case .result(let result):
            if let cont = pending.removeValue(forKey: result.requestId) {
                if result.ok {
                    cont.resume(returning: result)
                } else {
                    let code = result.error?.code ?? "error"
                    let message = result.error?.message ?? "Command failed"
                    cont.resume(throwing: WireError.commandFailed(code: code, message: message))
                }
            }
        }
    }

    private func handleReceiveFailure(_ error: Error) {
        for (_, cont) in pending {
            cont.resume(throwing: error)
        }
        pending.removeAll()
        if let c = helloContinuation {
            helloContinuation = nil
            c.resume(throwing: error)
        }
        setState(.failed(error.localizedDescription))
        task = nil
    }

    private func setState(_ new: ConnectionState) {
        state = new
        onState?(new)
    }

    private func newId() -> String { UUID().uuidString }

    private func decodeSessions(_ result: CommandResult) throws -> [SessionSummary] {
        guard let data = result.data?.objectValue,
              case .array(let arr) = data["sessions"]
        else {
            return []
        }
        return try arr.map { try decodeValue(SessionSummary.self, from: $0) }
    }

    private func decodeValue<T: Decodable>(_ type: T.Type, from value: JSONValue) throws -> T {
        let data = try encoder.encode(value)
        return try decoder.decode(T.self, from: data)
    }
}
