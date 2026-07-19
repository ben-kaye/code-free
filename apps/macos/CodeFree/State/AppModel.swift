import Foundation
import SwiftUI

/// Top-level shell state: host + client + sessions + transcript projection.
@MainActor
final class AppModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case starting
        case ready
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var connectionLabel: String = "Disconnected"
    @Published private(set) var sessions: [SessionSummary] = []
    @Published var selectedSessionId: String?
    @Published private(set) var transcript: [TranscriptItem] = []
    @Published private(set) var lastSeq: Int = 0
    @Published var composerText: String = ""
    @Published private(set) var isSending: Bool = false
    @Published var banner: String?

    private let host = OrchHost()
    private let client = OrchClient()
    private var paths: OrchHost.Paths?
    private var subscribedSessionId: String?
    private var startTask: Task<Void, Never>?

    var selectedSession: SessionSummary? {
        sessions.first { $0.id == selectedSessionId }
    }

    func start() {
        guard startTask == nil else { return }
        startTask = Task { await bootstrap() }
    }

    func shutdown() {
        startTask?.cancel()
        startTask = nil
        Task {
            await client.disconnect()
            host.stop()
        }
    }

    func restart() {
        shutdown()
        phase = .idle
        connectionLabel = "Disconnected"
        banner = nil
        startTask = Task { await bootstrap() }
    }

    // MARK: - Sessions

    func newSession() {
        Task { await createSession() }
    }

    func selectSession(_ id: String?) {
        guard let id else {
            selectedSessionId = nil
            transcript = []
            lastSeq = 0
            return
        }
        guard id != selectedSessionId else { return }
        selectedSessionId = id
        Task { await subscribe(to: id, afterSeq: 0, reset: true) }
    }

    func sendMessage() {
        let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        guard let sessionId = selectedSessionId else { return }
        isSending = true
        composerText = ""
        Task {
            defer { isSending = false }
            do {
                // Auto-title from first message if still default
                if let session = selectedSession, session.title == nil {
                    let title = String(text.prefix(48))
                    if let updated = try? await client.rename(sessionId: sessionId, title: title) {
                        if let idx = sessions.firstIndex(where: { $0.id == sessionId }) {
                            sessions[idx] = updated
                        }
                    }
                }
                try await client.send(sessionId: sessionId, text: text)
            } catch {
                banner = error.localizedDescription
                // Restore draft on failure
                if composerText.isEmpty { composerText = text }
            }
        }
    }

    // MARK: - Bootstrap

    private func bootstrap() async {
        phase = .starting
        connectionLabel = "Starting orchestrator…"
        banner = nil

        do {
            let paths = try OrchHost.Paths.default()
            self.paths = paths

            await client.setHandlers(
                onState: { [weak self] state in
                    Task { @MainActor in
                        self?.applyConnectionState(state)
                    }
                },
                onEvent: { [weak self] event in
                    Task { @MainActor in
                        self?.handleEvent(event)
                    }
                },
                onSnapshot: { [weak self] snap in
                    Task { @MainActor in
                        self?.handleSnapshot(snap)
                    }
                },
                onServerError: { [weak self] err in
                    Task { @MainActor in
                        self?.banner = "\(err.code): \(err.message)"
                    }
                }
            )

            connectionLabel = "Launching sidecar…"
            let info = try host.start(paths: paths)

            connectionLabel = "Connecting…"
            try await client.connect(endpoint: info.endpoint, token: info.token)

            let list = try await client.listSessions()
            sessions = list.sorted { $0.updatedAt > $1.updatedAt }
            phase = .ready
            connectionLabel = "Connected"

            if selectedSessionId == nil, let first = sessions.first {
                selectSession(first.id)
            } else if let id = selectedSessionId {
                await subscribe(to: id, afterSeq: 0, reset: true)
            }
        } catch {
            phase = .failed(error.localizedDescription)
            connectionLabel = "Error"
            banner = error.localizedDescription
        }
    }

    private func createSession() async {
        do {
            let cwd = FileManager.default.homeDirectoryForCurrentUser.path
            let session = try await client.createSession(cwd: cwd)
            sessions.insert(session, at: 0)
            selectedSessionId = session.id
            await subscribe(to: session.id, afterSeq: 0, reset: true)
        } catch {
            banner = error.localizedDescription
        }
    }

    private func subscribe(to sessionId: String, afterSeq: Int, reset: Bool) async {
        do {
            if let prev = subscribedSessionId, prev != sessionId {
                try? await client.unsubscribe(sessionId: prev)
            }
            if reset {
                transcript = []
                lastSeq = 0
            }
            subscribedSessionId = sessionId
            try await client.subscribe(sessionId: sessionId, afterSeq: afterSeq)
        } catch {
            banner = error.localizedDescription
        }
    }

    private func handleSnapshot(_ snap: SnapshotFrame) {
        guard snap.sessionId == selectedSessionId || selectedSessionId == nil else {
            // Still apply if it matches subscription
            guard snap.sessionId == subscribedSessionId else { return }
            return
        }
        if lastSeq == 0 {
            transcript = TranscriptReducer.reduce(snap.events)
        } else {
            for event in snap.events where event.seq > lastSeq {
                TranscriptReducer.apply(event, to: &transcript)
            }
        }
        lastSeq = max(lastSeq, snap.lastSeq)
        if let maxEvent = snap.events.map(\.seq).max() {
            lastSeq = max(lastSeq, maxEvent)
        }
    }

    private func handleEvent(_ event: EventFrame) {
        guard event.sessionId == subscribedSessionId || event.sessionId == selectedSessionId else {
            return
        }
        if event.seq <= lastSeq { return }
        TranscriptReducer.apply(event, to: &transcript)
        lastSeq = event.seq

        // Keep session list recency
        if let idx = sessions.firstIndex(where: { $0.id == event.sessionId }) {
            let s = sessions.remove(at: idx)
            sessions.insert(
                SessionSummary(
                    id: s.id,
                    title: s.title,
                    cwd: s.cwd,
                    harnessId: s.harnessId,
                    model: s.model,
                    createdAt: s.createdAt,
                    updatedAt: ISO8601DateFormatter().string(from: Date()),
                    lastSeq: event.seq
                ),
                at: 0
            )
        }
    }

    private func applyConnectionState(_ state: OrchClient.ConnectionState) {
        switch state {
        case .disconnected:
            connectionLabel = "Disconnected"
        case .connecting:
            connectionLabel = "Connecting…"
        case .authenticating:
            connectionLabel = "Authenticating…"
        case .connected:
            connectionLabel = "Connected"
            if case .ready = phase { banner = nil }
        case .failed(let msg):
            connectionLabel = "Connection lost"
            banner = msg
            phase = .failed(msg)
        }
    }
}
