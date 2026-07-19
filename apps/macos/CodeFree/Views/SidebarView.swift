import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var workspaces: WorkspaceStore
    /// Paths the user has collapsed; absent paths default to expanded.
    @State private var collapsedProjects: Set<String> = []
    @State private var archivedExpanded = false
    @State private var sessionPendingArchive: SessionSummary?
    @State private var projectPendingClose: String?
    @State private var renameTarget: SessionSummary?
    @State private var renameDraft = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Tasks")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Button {
                model.newTask()
            } label: {
                Label("New task", systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .disabled(!isReady)
            .keyboardShortcut("n", modifiers: [.command])
            .help("New task (⌘N)")
            .accessibilityLabel("New task")

            List(selection: Binding(
                get: { model.selectedSessionId },
                set: { model.selectSession($0) }
            )) {
                if !model.sessionsByWorkspacePath.isEmpty {
                    Section("Projects") {
                        ForEach(model.sessionsByWorkspacePath, id: \.path) { group in
                            DisclosureGroup(isExpanded: expansionBinding(for: group.path)) {
                                ForEach(group.sessions) { session in
                                    SessionRow(
                                        session: session,
                                        showPath: false,
                                        onArchive: { sessionPendingArchive = session },
                                        onRename: {
                                            renameTarget = session
                                            renameDraft = session.title ?? session.displayTitle
                                        }
                                    )
                                    .tag(session.id)
                                }
                            } label: {
                                WorkspaceGroupLabel(
                                    path: group.path,
                                    name: workspaceName(for: group.path),
                                    count: group.sessions.count,
                                    onClose: { projectPendingClose = group.path }
                                )
                            }
                        }
                    }
                }

                Section("Recents") {
                    if model.sessions.isEmpty {
                        Text(emptyLabel)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .listRowSeparator(.hidden)
                    } else if model.recentSessionsUnlisted.isEmpty {
                        Text("Tasks are listed under Projects above")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .listRowSeparator(.hidden)
                    } else {
                        ForEach(model.recentSessionsUnlisted) { session in
                            SessionRow(
                                session: session,
                                showPath: true,
                                onArchive: { sessionPendingArchive = session },
                                onRename: {
                                    renameTarget = session
                                    renameDraft = session.title ?? session.displayTitle
                                }
                            )
                            .tag(session.id)
                        }
                    }
                }

                if !model.archivedSessions.isEmpty {
                    Section {
                        DisclosureGroup(isExpanded: $archivedExpanded) {
                            ForEach(model.archivedSessions) { session in
                                SessionRow(
                                    session: session,
                                    showPath: true,
                                    showArchiveHint: true
                                )
                                .tag(session.id)
                                .foregroundStyle(.secondary)
                            }
                        } label: {
                            HStack {
                                Text("Archived")
                                Spacer()
                                Text("\(model.archivedSessions.count)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()
            Button {
                model.newProject()
            } label: {
                Label("New project", systemImage: "folder.badge.plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .disabled(!isReady)
            .help("Add a workspace folder")
            .accessibilityLabel("New project")
        }
        .background(.background)
        .confirmationDialog(
            "Archive this task?",
            isPresented: Binding(
                get: { sessionPendingArchive != nil },
                set: { if !$0 { sessionPendingArchive = nil } }
            ),
            titleVisibility: .visible,
            presenting: sessionPendingArchive
        ) { session in
            Button("Archive", role: .destructive) {
                model.archiveSession(session.id)
                sessionPendingArchive = nil
            }
            Button("Cancel", role: .cancel) {
                sessionPendingArchive = nil
            }
        } message: { session in
            Text(
                "“\(session.displayTitle)” moves to Archived and is permanently deleted after 7 days. There is no undo after that."
            )
        }
        .confirmationDialog(
            "Close this project?",
            isPresented: Binding(
                get: { projectPendingClose != nil },
                set: { if !$0 { projectPendingClose = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Close project", role: .destructive) {
                if let path = projectPendingClose {
                    model.closeProject(path: path)
                }
                projectPendingClose = nil
            }
            Button("Cancel", role: .cancel) {
                projectPendingClose = nil
            }
        } message: {
            Text("The project leaves the sidebar. Existing tasks stay under Recents.")
        }
        .alert(
            "Rename Task",
            isPresented: Binding(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } }
            )
        ) {
            TextField("Title", text: $renameDraft)
            Button("Save") {
                if let id = renameTarget?.id {
                    model.renameSession(id, title: renameDraft)
                }
                renameTarget = nil
            }
            Button("Cancel", role: .cancel) {
                renameTarget = nil
            }
        } message: {
            Text("Choose a short name for this task.")
        }
    }

    private func workspaceName(for path: String) -> String {
        let key = Workspace.normalizePath(path)
        if let ws = workspaces.workspaces.first(where: {
            Workspace.normalizePath($0.path) == key
        }) {
            return ws.displayName
        }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    private func expansionBinding(for path: String) -> Binding<Bool> {
        Binding(
            get: { !collapsedProjects.contains(path) },
            set: { expanded in
                if expanded {
                    collapsedProjects.remove(path)
                } else {
                    collapsedProjects.insert(path)
                }
            }
        )
    }

    private var isReady: Bool {
        if case .ready = model.phase { return true }
        return false
    }

    private var emptyLabel: String {
        switch model.phase {
        case .starting, .idle:
            return "Starting…"
        case .failed:
            return "Unavailable"
        case .ready:
            return "No tasks yet"
        }
    }
}

struct WorkspaceGroupLabel: View {
    let path: String
    let name: String
    let count: Int
    var onClose: (() -> Void)?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(name)
                .lineLimit(1)
            Spacer(minLength: 4)
            if count > 0 {
                Text("\(count)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .help(path)
        .accessibilityLabel("\(name), \(count) tasks")
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }
            Divider()
            Button("Close project…") {
                onClose?()
            }
        }
    }
}

struct SessionRow: View {
    let session: SessionSummary
    var showPath: Bool = true
    var showArchiveHint: Bool = false
    var onArchive: (() -> Void)?
    var onRename: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(session.displayTitle)
                .font(.body)
                .lineLimit(1)
            if showPath, let caption = pathCaption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            if showArchiveHint, let label = retentionLabel {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            if let onRename, !session.isArchived {
                Button("Rename…") { onRename() }
            }
            if let onArchive {
                Divider()
                Button("Archive task…", role: .destructive) {
                    onArchive()
                }
            }
        }
        .help(showArchiveHint ? "Archived — permanently deleted after 7 days" : session.displayTitle)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts = [session.displayTitle]
        if showPath, let caption = pathCaption {
            parts.append(caption)
        }
        if showArchiveHint, let label = retentionLabel {
            parts.append(label)
        }
        return parts.joined(separator: ", ")
    }

    /// Hide useless captions (`~` alone or empty).
    private var pathCaption: String? {
        let short = Workspace.displayPath(session.cwd)
        if short.isEmpty || short == "~" { return nil }
        return short
    }

    /// Days left until orch purges this archive (7-day retention).
    private var retentionLabel: String? {
        guard let archivedAt = session.archivedAt else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: archivedAt)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: archivedAt)
        }
        guard let date else { return "Deletes in 7 days" }
        let deadline = date.addingTimeInterval(7 * 24 * 60 * 60)
        let remaining = deadline.timeIntervalSince(Date())
        if remaining <= 0 { return "Deletes soon" }
        let days = Int(ceil(remaining / (24 * 60 * 60)))
        if days <= 1 { return "Deletes in 1 day" }
        return "Deletes in \(days) days"
    }
}
