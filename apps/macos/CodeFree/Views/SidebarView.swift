import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var workspaces: WorkspaceStore
    /// Paths the user has collapsed; absent paths default to expanded.
    @State private var collapsedProjects: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Code Free")
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
                                        onArchive: { model.archiveSession(session.id) }
                                    )
                                    .tag(session.id)
                                }
                            } label: {
                                WorkspaceGroupLabel(
                                    path: group.path,
                                    name: workspaceName(for: group.path),
                                    count: group.sessions.count,
                                    onClose: { model.closeProject(path: group.path) }
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
                    } else {
                        ForEach(model.sessions.prefix(20)) { session in
                            SessionRow(
                                session: session,
                                showPath: true,
                                onArchive: { model.archiveSession(session.id) }
                            )
                            .tag(session.id)
                        }
                    }
                }

                if !model.archivedSessions.isEmpty {
                    Section("Archived") {
                        ForEach(model.archivedSessions) { session in
                            SessionRow(
                                session: session,
                                showPath: true,
                                showArchiveHint: true
                            )
                            .tag(session.id)
                            .foregroundStyle(.secondary)
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
        }
        .background(.background)
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
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }
            Divider()
            Button("Close Project") {
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

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(session.displayTitle)
                .font(.body)
                .lineLimit(1)
            if showPath {
                Text(shortPath(session.cwd))
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
            if let onArchive {
                Button("Archive Task", role: .destructive) {
                    onArchive()
                }
            }
        }
        .help(showArchiveHint ? "Archived — permanently deleted after 7 days" : session.displayTitle)
    }

    private func shortPath(_ path: String) -> String {
        Workspace.displayPath(path)
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
        let days = max(0, Calendar.current.dateComponents([.day], from: Date(), to: deadline).day ?? 0)
        if days <= 0 { return "Deletes soon" }
        if days == 1 { return "Deletes in 1 day" }
        return "Deletes in \(days) days"
    }
}
