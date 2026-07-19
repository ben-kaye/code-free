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
    /// Human status for the local orchestrator. Only shown while not ready.
    @Published private(set) var connectionLabel: String = "Orchestrator offline"
    @Published private(set) var sessions: [SessionSummary] = []
    /// Soft-deleted tasks; orch purges after 7 days.
    @Published private(set) var archivedSessions: [SessionSummary] = []
    @Published var selectedSessionId: String?
    @Published private(set) var transcript: [TranscriptItem] = []
    @Published private(set) var lastSeq: Int = 0
    @Published var composerText: String = ""
    @Published private(set) var isSending: Bool = false
    /// True while the first snapshot for the selected session is loading.
    @Published private(set) var isLoadingTranscript: Bool = false
    @Published var banner: UserBanner?

    /// From `harness.list`. Empty until an adapter is registered (honest empty UI).
    @Published private(set) var harnesses: [HarnessInfo] = []
    /// Selected harness for new tasks. Nil when none available or user cleared.
    @Published var selectedHarnessId: String?

    /// From `models.list` for the selected harness. Empty when cap off or none registered.
    /// Refetched when the picker opens, harness changes, and before starting a task — not a sticky snapshot.
    @Published private(set) var models: [ModelInfo] = []
    /// True while a `models.list` request is in flight for the selected harness.
    @Published private(set) var isLoadingModels: Bool = false
    /// Selected model id for new tasks (matrix row).
    @Published var selectedModelId: String?
    /// Selected thinking / reasoning effort id (matrix column). Nil when model has none.
    @Published var selectedReasoningEffortId: String?

    /// Shell-owned project bookmarks (cwd defaults). Orch only stores session cwd.
    let workspaces = WorkspaceStore()

    private let host = OrchHost()
    private let client = OrchClient()
    private var paths: OrchHost.Paths?
    private var subscribedSessionId: String?
    private var startTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    /// Bumped on navigation so in-flight `startTaskFromHome` can bail after each await.
    private var taskOpGeneration: UInt64 = 0
    /// Bumped when the selected harness changes or a new models fetch starts; drops stale replies.
    private var modelsFetchGeneration: UInt64 = 0
    /// True between status.turn_start and turn_end / session.error — drives hybrid quit.
    private var turnActive = false
    /// Suppress reconnect storms while bootstrap/restart owns the connection.
    private var suppressAutoReconnect = false

    var selectedSession: SessionSummary? {
        sessions.first { $0.id == selectedSessionId }
            ?? archivedSessions.first { $0.id == selectedSessionId }
    }

    var selectedHarness: HarnessInfo? {
        guard let selectedHarnessId else { return nil }
        return harnesses.first { $0.id == selectedHarnessId }
    }

    var selectedModel: ModelInfo? {
        guard let selectedModelId else { return nil }
        return models.first { $0.id == selectedModelId }
    }

    /// Label for the harness/model chip on the home orchestrator.
    var harnessModelChipTitle: String {
        if let model = selectedModel {
            return model.selectionLabel(effortId: selectedReasoningEffortId)
        }
        if let harness = selectedHarness {
            return harness.name
        }
        return "Choose harness"
    }

    /// Durable `session.model` value for create (id or id#effort).
    var selectedModelRef: String? {
        guard let selectedModelId else { return nil }
        let effort = selectedModel?.supportsReasoning == true ? selectedReasoningEffortId : nil
        return ModelRef.encode(modelId: selectedModelId, effortId: effort)
    }

    func selectHarness(_ id: String?) {
        if let id {
            guard harnesses.contains(where: { $0.id == id }) else { return }
            if selectedHarnessId == id {
                // Same harness — still refresh so offerings can change while the picker is open.
                Task { await refreshModels() }
                return
            }
            selectedHarnessId = id
            // Clear catalog for the previous harness; fetch is race-guarded by generation.
            models = []
            selectedModelId = nil
            selectedReasoningEffortId = nil
            Task { await refreshModels() }
        } else {
            modelsFetchGeneration &+= 1
            selectedHarnessId = nil
            models = []
            selectedModelId = nil
            selectedReasoningEffortId = nil
            isLoadingModels = false
        }
    }

    func selectModel(_ modelId: String, effortId: String?) {
        guard models.contains(where: { $0.id == modelId }) else { return }
        selectedModelId = modelId
        if let model = models.first(where: { $0.id == modelId }), model.supportsReasoning {
            if let effortId, model.efforts.contains(where: { $0.id == effortId }) {
                selectedReasoningEffortId = effortId
            } else {
                selectedReasoningEffortId = model.preferredEffortId
            }
        } else {
            selectedReasoningEffortId = nil
        }
    }

    /// Re-fetch the model catalog for the current harness (picker open / harness change / pre-create).
    func refreshModelsCatalog() {
        Task { await refreshModels() }
    }

    /// Awaitable catalog refresh for SwiftUI `.task` and pre-create paths.
    func refreshModelsCatalogAsync() async {
        await refreshModels()
    }

    /// Active projects for the sidebar: every non-closed bookmark, plus session-only paths.
    /// Bookmarks always appear (empty task lists included) so New project shows immediately.
    var sessionsByWorkspacePath: [(path: String, sessions: [SessionSummary])] {
        var order: [String] = []
        var buckets: [String: [SessionSummary]] = [:]
        for session in sessions {
            let key = Workspace.normalizePath(session.cwd)
            if buckets[key] == nil {
                order.append(key)
                buckets[key] = []
            }
            buckets[key, default: []].append(session)
        }
        // Closed projects stay out (sessions remain under Recents).
        var result: [(path: String, sessions: [SessionSummary])] = []
        var seen = Set<String>()
        for ws in workspaces.workspaces {
            let key = Workspace.normalizePath(ws.path)
            if workspaces.isClosed(key) { continue }
            result.append((key, buckets[key] ?? []))
            seen.insert(key)
        }
        for path in order where !seen.contains(path) {
            if workspaces.isClosed(path) { continue }
            if let list = buckets[path] {
                result.append((path, list))
            }
        }
        return result
    }

    /// Recent tasks not already listed under Projects (no double-listing).
    var recentSessionsUnlisted: [SessionSummary] {
        let projectIds = Set(sessionsByWorkspacePath.flatMap(\.sessions).map(\.id))
        return sessions.filter { !projectIds.contains($0.id) }
    }

    /// Make a bookmarked project the active cwd and show the home composer (new task).
    /// Does not open an existing session — folder click is "new chat here", not resume.
    func activateProject(path: String) {
        let key = Workspace.normalizePath(path)
        guard !key.isEmpty, !workspaces.isClosed(key) else { return }
        if let ws = workspaces.workspaces.first(where: {
            Workspace.normalizePath($0.path) == key
        }) {
            workspaces.selectAndTouch(ws.id)
        } else {
            workspaces.add(path: key, select: true)
        }
        // Clear any stale session-error banner from a previous selection race.
        banner = nil
        newTask()
    }

    /// Present a user-facing banner (replaces any current one).
    func presentBanner(_ banner: UserBanner) {
        self.banner = banner
    }

    func dismissBanner() {
        banner = nil
    }

    /// Run the banner's primary recovery action, then dismiss.
    func performBannerAction(_ action: UserBanner.Action) {
        banner = nil
        switch action {
        case .newTask:
            newTask()
        case .restart:
            restart()
        }
    }

    private func presentError(_ error: Error) {
        if let wire = error as? WireError, case .commandFailed(let code, _) = wire,
           code == "session_not_found"
        {
            handleSessionMissing()
        }
        presentBanner(UserBanner.from(error: error))
    }

    private func presentServerError(_ err: ErrorFrame) {
        if err.code == "session_not_found" {
            if let sid = err.sessionId {
                sessions.removeAll { $0.id == sid }
                archivedSessions.removeAll { $0.id == sid }
                if selectedSessionId == sid {
                    newTask()
                }
            } else {
                handleSessionMissing()
            }
        }
        presentBanner(UserBanner.from(code: err.code, message: err.message))
    }

    /// Drop a dead selection when the orch no longer has the session.
    private func handleSessionMissing() {
        if let id = selectedSessionId {
            sessions.removeAll { $0.id == id }
            archivedSessions.removeAll { $0.id == id }
            newTask()
        }
    }

    /// Close a project from the sidebar. Does not delete sessions.
    func closeProject(path: String) {
        workspaces.close(path: path)
        workspaces.ensureSelection()
    }

    /// Archive a task (soft-delete). Removed from Projects/Recents; purged after 7 days by orch.
    /// Archived tasks remain under Archived for retention (no confirm — soft-delete is reversible in the window).
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
                presentError(error)
            }
        }
    }

    /// Rename a task. Empty title is rejected.
    func renameSession(_ id: String, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task {
            do {
                let updated = try await client.rename(sessionId: id, title: trimmed)
                if let idx = sessions.firstIndex(where: { $0.id == id }) {
                    sessions[idx] = updated
                } else if let idx = archivedSessions.firstIndex(where: { $0.id == id }) {
                    archivedSessions[idx] = updated
                }
            } catch {
                presentError(error)
            }
        }
    }

    /// Signature for scroll/auto-follow: changes when count, last text, or last seq changes.
    var transcriptContentSignature: String {
        guard let last = transcript.last else {
            return "empty-\(isLoadingTranscript)"
        }
        return "\(transcript.count)|\(last.id)|\(last.seq)|\(last.text.count)"
    }

    var windowTitle: String {
        if let session = selectedSession {
            return session.displayTitle
        }
        return "Code Free"
    }

    func start() {
        guard startTask == nil else { return }
        startTask = Task { await bootstrap() }
    }

    /// Hybrid lifecycle: leave orch running when a turn is in flight (reattach on next launch).
    var shouldLeaveOrchRunning: Bool {
        turnActive || isSending
    }

    /// Disconnect WS. Idle quit SIGTERM's the sidecar; busy quit leaves it running.
    func shutdown(leaveOrchRunning: Bool? = nil) {
        let leave = leaveOrchRunning ?? shouldLeaveOrchRunning
        suppressAutoReconnect = true
        startTask?.cancel()
        startTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        // Host stop is sync so terminate can SIGTERM before process exit.
        host.stop(leaveRunning: leave)
        Task {
            await client.disconnect(notify: false)
        }
    }

    func restart() {
        // Forced restart always stops the sidecar, even mid-turn.
        shutdown(leaveOrchRunning: false)
        phase = .idle
        connectionLabel = "Orchestrator offline"
        banner = nil
        turnActive = false
        suppressAutoReconnect = false
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
        isLoadingTranscript = false
        subscribedSessionId = nil
        // Turn activity is per subscribed session; home has no live turn.
        turnActive = false
        if let prev {
            // Leaving a task is intentional; unsubscribe is best-effort and must not
            // surface "task is no longer available" on the home composer.
            Task {
                try? await client.unsubscribe(sessionId: prev)
            }
        }
    }

    /// Add a workspace folder (New project). Always lands in the sidebar; becomes active cwd.
    func newProject() {
        guard workspaces.pickAndAdd() != nil else { return }
        newTask()
    }

    func selectSession(_ id: String?) {
        guard let id else {
            newTask()
            return
        }
        guard id != selectedSessionId else { return }
        // Only real task ids subscribe. Sidebar project rows use path as ForEach id;
        // List can surface that as selection — treat as "new task in this project".
        guard let session = sessions.first(where: { $0.id == id })
            ?? archivedSessions.first(where: { $0.id == id })
        else {
            let key = Workspace.normalizePath(id)
            let isProject = workspaces.workspaces.contains {
                Workspace.normalizePath($0.path) == key
            } || sessionsByWorkspacePath.contains { $0.path == key }
            if isProject {
                activateProject(path: key)
            }
            return
        }
        invalidateInFlightTaskOps()
        selectedSessionId = id
        if let ws = workspaces.workspaces.first(where: {
            Workspace.normalizePath($0.path) == Workspace.normalizePath(session.cwd)
        }) {
            workspaces.select(ws.id)
        } else if !session.isArchived {
            workspaces.rememberPath(session.cwd)
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
            presentBanner(.info("Archived tasks are read-only"))
            return
        }
        isSending = true
        composerText = ""
        Task {
            defer { isSending = false }
            do {
                // Auto-title from first message if still default
                if let session = selectedSession, session.title == nil {
                    let title = SessionSummary.titleFromMessage(text)
                    if let updated = try? await client.rename(sessionId: sessionId, title: title) {
                        if let idx = sessions.firstIndex(where: { $0.id == sessionId }) {
                            sessions[idx] = updated
                        }
                    }
                }
                try await client.send(sessionId: sessionId, text: text)
            } catch {
                presentError(error)
                // Restore draft on failure
                if composerText.isEmpty { composerText = text }
            }
        }
    }

    /// Home composer: create session in selected workspace, then send the first message.
    /// Caller (home UI) should resolve a workspace before calling when none is selected.
    func startTaskFromHome() {
        let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        guard case .ready = phase else { return }

        guard let ws = workspaces.selected else {
            presentBanner(.warning("Choose a workspace folder first"))
            return
        }

        taskOpGeneration &+= 1
        let generation = taskOpGeneration
        isSending = true
        composerText = ""
        let title = SessionSummary.titleFromMessage(text)
        Task {
            defer {
                if generation == taskOpGeneration {
                    isSending = false
                }
            }
            do {
                // Fresh catalog so a harness that updated offerings mid-session is used.
                await refreshModels()
                guard generation == taskOpGeneration, selectedSessionId == nil else { return }
                let session = try await client.createSession(
                    cwd: ws.path,
                    title: title,
                    harnessId: selectedHarnessId,
                    model: selectedModelRef
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
                // Switch into the task as soon as it exists so start doesn't linger on home.
                withAnimation(.easeInOut(duration: 0.18)) {
                    selectedSessionId = session.id
                }
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
                presentError(error)
                if composerText.isEmpty { composerText = text }
            }
        }
    }

    // MARK: - Bootstrap

    private func bootstrap() async {
        phase = .starting
        connectionLabel = "Starting orchestrator…"
        banner = nil
        suppressAutoReconnect = true
        defer { suppressAutoReconnect = false }

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
                        self?.presentServerError(err)
                    }
                }
            )

            connectionLabel = "Launching orchestrator…"
            let info = try host.start(paths: paths)
            if !info.owned {
                connectionLabel = "Reattaching to orchestrator…"
            } else {
                connectionLabel = "Connecting to orchestrator…"
            }
            try await client.connect(endpoint: info.endpoint, token: info.token)

            try await refreshSessionLists()
            for session in sessions {
                workspaces.rememberPath(session.cwd)
            }
            workspaces.ensureSelection()
            await refreshHarnesses()
            phase = .ready
            // Healthy: UI hides status; keep label for a11y / debug if needed.
            connectionLabel = "Orchestrator ready"
            if let loadError = workspaces.loadError {
                presentBanner(.warning(loadError))
            }

            // Open on the home orchestrator. Resuming a session is an explicit sidebar click.
            // Reattach mid-session uses afterSeq so gap-fill doesn't wipe live transcript.
            if let id = selectedSessionId {
                let after = lastSeq > 0 ? lastSeq : 0
                await subscribe(to: id, afterSeq: after, reset: lastSeq == 0)
            }
        } catch {
            phase = .failed(error.localizedDescription)
            connectionLabel = "Orchestrator unavailable"
            presentError(error)
        }
    }

    private func refreshSessionLists() async throws {
        let list = try await client.listSessions(filter: "active")
        sessions = list.sorted { $0.updatedAt > $1.updatedAt }
        let archived = try await client.listSessions(filter: "archived")
        archivedSessions = archived.sorted {
            ($0.archivedAt ?? $0.updatedAt) > ($1.archivedAt ?? $1.updatedAt)
        }
    }

    /// WS drop recovery: reattach/spawn host, reconnect, resubscribe afterSeq (gap fill).
    private func scheduleReconnect() {
        guard !suppressAutoReconnect else { return }
        if reconnectTask != nil { return }
        reconnectTask = Task { [weak self] in
            guard let self else { return }
            await self.runReconnectLoop()
            await MainActor.run { self.reconnectTask = nil }
        }
    }

    private func runReconnectLoop() async {
        let delaysNs: [UInt64] = [
            300_000_000, // 0.3s
            800_000_000,
            1_500_000_000,
            3_000_000_000,
            5_000_000_000,
        ]
        for (attempt, delay) in delaysNs.enumerated() {
            if Task.isCancelled || suppressAutoReconnect { return }
            await MainActor.run {
                self.phase = .starting
                self.connectionLabel = attempt == 0
                    ? "Reconnecting…"
                    : "Reconnecting… (\(attempt + 1)/\(delaysNs.count))"
            }
            try? await Task.sleep(nanoseconds: delay)
            if Task.isCancelled || suppressAutoReconnect { return }
            do {
                try await reconnectOnce()
                return
            } catch {
                continue
            }
        }
        await MainActor.run {
            self.phase = .failed("Connection lost")
            self.connectionLabel = "Orchestrator connection lost"
            self.presentBanner(
                .error("Lost connection to the local orchestrator", action: .restart)
            )
        }
    }

    private func reconnectOnce() async throws {
        guard let paths else {
            throw HostError.noAppSupport
        }
        suppressAutoReconnect = true
        defer { suppressAutoReconnect = false }

        let info = try host.start(paths: paths)
        try await client.connect(endpoint: info.endpoint, token: info.token)
        try await refreshSessionLists()
        await refreshHarnesses()

        phase = .ready
        connectionLabel = "Orchestrator ready"
        banner = nil

        // Gap-fill: keep projected transcript; snapshot only events after lastSeq.
        if let id = selectedSessionId {
            await subscribe(to: id, afterSeq: lastSeq, reset: false)
        }
    }

    private func subscribe(to sessionId: String, afterSeq: Int, reset: Bool) async {
        if reset {
            isLoadingTranscript = true
            transcript = []
            lastSeq = 0
            turnActive = false
        }
        do {
            if let prev = subscribedSessionId, prev != sessionId {
                // Best-effort; missing session is not a user-facing failure when switching.
                try? await client.unsubscribe(sessionId: prev)
            }
            // User may have navigated away during unsubscribe.
            guard selectedSessionId == sessionId else {
                if isLoadingTranscript, selectedSessionId != sessionId {
                    isLoadingTranscript = false
                }
                return
            }
            subscribedSessionId = sessionId
            try await client.subscribe(sessionId: sessionId, afterSeq: afterSeq)
            // Network await can complete after a later selection; drop the orphan sub.
            guard selectedSessionId == sessionId else {
                if subscribedSessionId == sessionId {
                    subscribedSessionId = nil
                }
                isLoadingTranscript = false
                try? await client.unsubscribe(sessionId: sessionId)
                return
            }
            // Snapshot may arrive via handler before or after this returns; clear loading
            // once subscribe succeeds so empty sessions don't spin forever.
            isLoadingTranscript = false
        } catch {
            if selectedSessionId == sessionId {
                isLoadingTranscript = false
            }
            presentError(error)
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
            recomputeTurnActive(from: snap.events)
        } else {
            for event in snap.events where event.seq > lastSeq {
                TranscriptReducer.apply(event, to: &transcript)
                updateTurnActive(from: event)
            }
        }
        lastSeq = max(lastSeq, snap.lastSeq)
        if let maxEvent = snap.events.map(\.seq).max() {
            lastSeq = max(lastSeq, maxEvent)
        }
        if snap.sessionId == selectedSessionId {
            isLoadingTranscript = false
        }
    }

    private func recomputeTurnActive(from events: [EventFrame]) {
        var active = false
        for event in events {
            switch event.type {
            case "status.turn_start":
                active = true
            case "status.turn_end", "session.error", "session.ended":
                active = false
            default:
                break
            }
        }
        turnActive = active
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
            await refreshModels()
        } catch {
            harnesses = []
            selectedHarnessId = nil
            models = []
            selectedModelId = nil
            selectedReasoningEffortId = nil
            // Surface only if we are otherwise ready — bootstrap will set banner on hard fail.
            if case .ready = phase {
                presentError(error)
            }
        }
    }

    /// Reload model catalog for the selected harness. Driven by `models_list` cap.
    /// Always hits orch → adapter (no shell cache) so updated harness offerings appear.
    private func refreshModels() async {
        modelsFetchGeneration &+= 1
        let generation = modelsFetchGeneration
        let harnessId = selectedHarnessId

        guard let harness = selectedHarness, harness.supportsModelsList else {
            if generation == modelsFetchGeneration {
                models = []
                selectedModelId = nil
                selectedReasoningEffortId = nil
                isLoadingModels = false
            }
            return
        }

        isLoadingModels = true
        defer {
            if generation == modelsFetchGeneration {
                isLoadingModels = false
            }
        }

        do {
            let list = try await client.listModels(harnessId: harness.id)
            // Drop stale replies (harness switched or a newer fetch started).
            guard generation == modelsFetchGeneration, selectedHarnessId == harnessId else { return }
            applyModelsList(list)
        } catch {
            guard generation == modelsFetchGeneration, selectedHarnessId == harnessId else { return }
            // Keep the last good catalog on refresh failure; only wipe when we had nothing.
            if models.isEmpty {
                selectedModelId = nil
                selectedReasoningEffortId = nil
            }
            if case .ready = phase {
                presentError(error)
            }
        }
    }

    /// Apply a fresh models.list payload, preserving selection when still valid.
    private func applyModelsList(_ list: [ModelInfo]) {
        models = list
        if let selectedModelId, let match = list.first(where: { $0.id == selectedModelId }) {
            if match.supportsReasoning {
                if let selectedReasoningEffortId,
                   match.efforts.contains(where: { $0.id == selectedReasoningEffortId })
                {
                    // keep effort
                } else {
                    selectedReasoningEffortId = match.preferredEffortId
                }
            } else {
                selectedReasoningEffortId = nil
            }
        } else if let first = list.first {
            selectedModelId = first.id
            selectedReasoningEffortId = first.preferredEffortId
        } else {
            selectedModelId = nil
            selectedReasoningEffortId = nil
        }
    }

    private func handleEvent(_ event: EventFrame) {
        guard event.sessionId == subscribedSessionId || event.sessionId == selectedSessionId else {
            return
        }
        if event.seq <= lastSeq { return }
        TranscriptReducer.apply(event, to: &transcript)
        lastSeq = event.seq
        updateTurnActive(from: event)

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

    private func updateTurnActive(from event: EventFrame) {
        switch event.type {
        case "status.turn_start":
            turnActive = true
        case "status.turn_end", "session.error", "session.ended":
            turnActive = false
        default:
            break
        }
    }

    private func applyConnectionState(_ state: OrchClient.ConnectionState) {
        switch state {
        case .disconnected:
            // Only surface while not already in a hard failed phase with its own copy.
            if case .ready = phase {
                connectionLabel = "Orchestrator offline"
            } else if case .failed = phase {
                // keep existing failure label
            } else {
                connectionLabel = "Orchestrator offline"
            }
        case .connecting:
            connectionLabel = "Connecting to orchestrator…"
        case .authenticating:
            connectionLabel = "Authenticating with orchestrator…"
        case .connected:
            connectionLabel = "Orchestrator ready"
            if case .ready = phase { banner = nil }
        case .failed:
            if suppressAutoReconnect {
                connectionLabel = "Orchestrator connection lost"
                return
            }
            // Auto-resubscribe afterSeq when the live WS drops (harness may still be running).
            if case .ready = phase {
                phase = .starting
                connectionLabel = "Reconnecting…"
                scheduleReconnect()
            } else if case .starting = phase {
                // Mid-reconnect failure is handled by the reconnect loop.
                connectionLabel = "Reconnecting…"
            } else {
                connectionLabel = "Orchestrator connection lost"
                phase = .failed("Connection lost")
                presentBanner(.error("Lost connection to the local orchestrator", action: .restart))
            }
        }
    }
}
