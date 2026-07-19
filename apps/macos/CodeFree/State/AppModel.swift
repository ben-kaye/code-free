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
    /// Soft-deleted tasks; orch purges after 7 days.
    @Published private(set) var archivedSessions: [SessionSummary] = []
    @Published var selectedSessionId: String?
    @Published private(set) var transcript: [TranscriptItem] = []
    @Published private(set) var lastSeq: Int = 0
    @Published var composerText: String = ""
    @Published private(set) var isSending: Bool = false
    @Published var banner: String?

    /// From `harness.list`. Empty until an adapter is registered (honest empty UI).
    @Published private(set) var harnesses: [HarnessInfo] = []
    /// Selected harness for new tasks. Nil when none available or user cleared.
    @Published var selectedHarnessId: String?

    /// Shell-owned project bookmarks (cwd defaults). Orch only stores session cwd.
    let workspaces = WorkspaceStore()

    private let host = OrchHost()
    private let client = OrchClient()
    private var paths: OrchHost.Paths?
    private var subscribedSessionId: String?
    private var startTask: Task<Void, Never>?
    /// Bumped on navigation so in-flight `startTaskFromHome` can bail after each await.
    private var taskOpGeneration: UInt64 = 0

    var selectedSession: SessionSummary? {
        sessions.first { $0.id == selectedSessionId }
            ?? archivedSessions.first { $0.id == selectedSessionId }
    }

    var selectedHarness: HarnessInfo? {
        guard let selectedHarnessId else { return nil }
        return harnesses.first { $0.id == selectedHarnessId }
    }

    func selectHarness(_ id: String?) {
        if let id {
            guard harnesses.contains(where: { $0.id == id }) else { return }
            selectedHarnessId = id
        } else {
            selectedHarnessId = nil
        }
    }

    /// Sessions grouped by normalized workspace path (Projects section).
    var sessionsByWorkspacePath: [(path: String, sessions: [SessionSummary])] {
        var order: [String] = []
        var buckets: [String: [SessionSummary]] = [:]
        for session in sessions {
            let key = Workspace.normalizePath(session.cwd)
            if buckets[key] == nil {
                order.append(key)
                buckets[key] = []
            }
            buckets[key]?.append(session)
        }
        // Prefer bookmarked workspace order, then remaining by recency of first session.
        // Closed projects stay out of this list (sessions remain under Recents).
        var result: [(path: String, sessions: [SessionSummary])] = []
        var seen = Set<String>()
        for ws in workspaces.workspaces {
            let key = Workspace.normalizePath(ws.path)
            if workspaces.isClosed(key) { continue }
            if let list = buckets[key], !list.isEmpty {
                result.append((key, list))
                seen.insert(key)
            }
        }
        for path in order where !seen.contains(path) {
            if workspaces.isClosed(path) { continue }
            if let list = buckets[path] {
                result.append((path, list))
            }
        }
        return result
    }

    /// Close a project from the sidebar. Does not delete sessions.
    func closeProject(path: String) {
        workspaces.close(path: path)
        workspaces.ensureSelection()
    }

    /// Archive a task (soft-delete). Removed from Projects/Recents; purged after 7 days by orch.
    func archiveSession(_ id: String) {
        Task {
            do {
                let archived = try await client.archiveSession(sessionId: id)
                sessions.removeAll { $0.id == id }
                archivedSessions.removeAll { $0.id == id }
                archivedSessions.insert(archived, at: 0)
                if selectedSessionId == id {
                    newTask()
                }
            } catch {
                banner = error.localizedDescription
            }
        }
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

    // MARK: - Tasks (sessions)

    /// Show the home orchestrator (new task) — deselect current session.
    func newTask() {
        invalidateInFlightTaskOps()
        workspaces.ensureSelection()
        let prev = subscribedSessionId
        selectedSessionId = nil
        transcript = []
        lastSeq = 0
        subscribedSessionId = nil
        if let prev {
            Task {
                do {
                    try await client.unsubscribe(sessionId: prev)
                } catch {
                    banner = error.localizedDescription
                }
            }
        }
    }

    /// Add a workspace folder (New project).
    func newProject() {
        _ = workspaces.pickAndAdd()
    }

    func selectSession(_ id: String?) {
        guard let id else {
            newTask()
            return
        }
        guard id != selectedSessionId else { return }
        invalidateInFlightTaskOps()
        selectedSessionId = id
        if let session = sessions.first(where: { $0.id == id })
            ?? archivedSessions.first(where: { $0.id == id })
        {
            if let ws = workspaces.workspaces.first(where: {
                Workspace.normalizePath($0.path) == Workspace.normalizePath(session.cwd)
            }) {
                workspaces.select(ws.id)
            } else if !session.isArchived {
                workspaces.rememberPath(session.cwd)
            }
        }
        Task { await subscribe(to: id, afterSeq: 0, reset: true) }
    }

    func sendMessage() {
        let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        guard let sessionId = selectedSessionId else {
            startTaskFromHome()
            return
        }
        if selectedSession?.isArchived == true {
            banner = "Archived tasks are read-only"
            return
        }
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

    /// Home composer: create session in selected workspace, then send the first message.
    func startTaskFromHome() {
        let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        guard case .ready = phase else { return }

        if workspaces.selected == nil {
            guard workspaces.pickAndAdd() != nil else { return }
        }
        guard let ws = workspaces.selected else {
            banner = "Choose a workspace folder first"
            return
        }

        taskOpGeneration &+= 1
        let generation = taskOpGeneration
        isSending = true
        composerText = ""
        let title = String(text.prefix(48))
        Task {
            defer {
                if generation == taskOpGeneration {
                    isSending = false
                }
            }
            do {
                let session = try await client.createSession(
                    cwd: ws.path,
                    title: title,
                    harnessId: selectedHarnessId
                )
                // User navigated away (home → other session, or New task) — keep the
                // created session in the list but do not steal selection/subscription.
                guard generation == taskOpGeneration, selectedSessionId == nil else {
                    if !sessions.contains(where: { $0.id == session.id }) {
                        sessions.insert(session, at: 0)
                    }
                    return
                }
                sessions.insert(session, at: 0)
                selectedSessionId = session.id
                workspaces.touch(ws.id)
                workspaces.rememberPath(session.cwd)
                await subscribe(to: session.id, afterSeq: 0, reset: true)
                // Subscribe may complete after the user left home; drop the orphan sub.
                guard generation == taskOpGeneration, selectedSessionId == session.id else {
                    if subscribedSessionId == session.id {
                        subscribedSessionId = nil
                        transcript = []
                        lastSeq = 0
                        Task { try? await client.unsubscribe(sessionId: session.id) }
                    }
                    return
                }
                try await client.send(sessionId: session.id, text: text)
            } catch {
                guard generation == taskOpGeneration else { return }
                banner = error.localizedDescription
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

            let list = try await client.listSessions(filter: "active")
            sessions = list.sorted { $0.updatedAt > $1.updatedAt }
            let archived = try await client.listSessions(filter: "archived")
            archivedSessions = archived.sorted {
                ($0.archivedAt ?? $0.updatedAt) > ($1.archivedAt ?? $1.updatedAt)
            }
            for session in sessions {
                workspaces.rememberPath(session.cwd)
            }
            workspaces.ensureSelection()
            await refreshHarnesses()
            phase = .ready
            connectionLabel = "Connected"
            if let loadError = workspaces.loadError {
                banner = loadError
            }

            // Open on the home orchestrator. Resuming a session is an explicit sidebar click.
            if let id = selectedSessionId {
                await subscribe(to: id, afterSeq: 0, reset: true)
            }
        } catch {
            phase = .failed(error.localizedDescription)
            connectionLabel = "Error"
            banner = error.localizedDescription
        }
    }

    private func subscribe(to sessionId: String, afterSeq: Int, reset: Bool) async {
        do {
            if let prev = subscribedSessionId, prev != sessionId {
                try? await client.unsubscribe(sessionId: prev)
            }
            // User may have navigated away during unsubscribe.
            guard selectedSessionId == sessionId else { return }
            if reset {
                transcript = []
                lastSeq = 0
            }
            subscribedSessionId = sessionId
            try await client.subscribe(sessionId: sessionId, afterSeq: afterSeq)
            // Network await can complete after a later selection; drop the orphan sub.
            guard selectedSessionId == sessionId else {
                if subscribedSessionId == sessionId {
                    subscribedSessionId = nil
                }
                try? await client.unsubscribe(sessionId: sessionId)
                return
            }
        } catch {
            banner = error.localizedDescription
        }
    }

    private func handleSnapshot(_ snap: SnapshotFrame) {
        // Only apply for the active subscription/selection — never when home has
        // cleared both (nil selection used to accept any late snapshot).
        guard snap.sessionId == subscribedSessionId || snap.sessionId == selectedSessionId else {
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

    private func invalidateInFlightTaskOps() {
        taskOpGeneration &+= 1
        isSending = false
    }

    /// Reload harness catalog from orch. Keeps selection when still present.
    private func refreshHarnesses() async {
        do {
            let list = try await client.listHarnesses()
            harnesses = list
            if let selectedHarnessId, list.contains(where: { $0.id == selectedHarnessId }) {
                // keep
            } else {
                selectedHarnessId = list.first?.id
            }
        } catch {
            harnesses = []
            selectedHarnessId = nil
            // Surface only if we are otherwise ready — bootstrap will set banner on hard fail.
            if case .ready = phase {
                banner = error.localizedDescription
            }
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
                    lastSeq: event.seq,
                    archivedAt: s.archivedAt
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
