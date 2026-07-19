import SwiftUI

// MARK: - Home / orchestrator

/// Centered new-task surface, or full-pane recovery when the orchestrator is down.
struct NewTaskHomeView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var workspaces: WorkspaceStore
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if case .failed(let message) = model.phase {
                failedPane(message: message)
            } else {
                homePane
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var homePane: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 48)
                .frame(maxHeight: 120)

            VStack(spacing: 22) {
                greeting
                homeComposer
                    .frame(maxWidth: 680)
                selectors
                Text("⌘↩ to start · Return for newline")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 32)

            Spacer(minLength: 48)
        }
        .onAppear {
            workspaces.ensureSelection()
            if isReady { focused = true }
        }
    }

    private func failedPane(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("Orchestrator unavailable")
                .font(.title2.weight(.semibold))
            Text(message.isEmpty ? "Could not connect to the local orchestrator." : message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button("Restart") {
                model.restart()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut("r", modifiers: [.command])
            .accessibilityLabel("Restart orchestrator")
        }
        .padding(32)
        .accessibilityElement(children: .combine)
    }

    private var greeting: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 48, height: 48)
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .accessibilityHidden(true)
            Text("What are we doing today?")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            if let subtitle {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var subtitle: String? {
        if let name = workspaces.selected?.displayName {
            return "Start a task in \(name)"
        }
        switch model.phase {
        case .ready:
            return "Choose a folder, then describe the task"
        case .starting, .idle:
            return "Connecting…"
        case .failed:
            return nil
        }
    }

    private var homeComposer: some View {
        MessageComposerField(
            text: $model.composerText,
            placeholder: "Ask anything…",
            canSend: canSend,
            isSending: model.isSending,
            focused: $focused,
            onSend: { model.startTaskFromHome() }
        )
        .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
        .opacity(isReady ? 1 : 0.7)
    }

    private var selectors: some View {
        HStack(spacing: 10) {
            WorkspaceSelectorMenu()
            HarnessSelectorMenu()
            // Honest local-only badge — not a fake multi-environment menu.
            LocalEnvironmentBadge()
        }
    }

    private var isReady: Bool {
        if case .ready = model.phase { return true }
        return false
    }

    private var canSend: Bool {
        guard isReady else { return false }
        guard !model.isSending else { return false }
        return !model.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Shared selector chip

struct SelectorChipLabel: View {
    let systemImage: String
    let title: String
    var detail: String? = nil
    var showsChevron: Bool = true

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title)
                .font(.callout.weight(.medium))
                .lineLimit(1)
            if let detail, !detail.isEmpty, detail != title {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            if showsChevron {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.05), in: Capsule())
        .overlay(
            Capsule().strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

// MARK: - Workspace selector

struct WorkspaceSelectorMenu: View {
    @EnvironmentObject private var workspaces: WorkspaceStore
    @State private var confirmClose = false

    var body: some View {
        Menu {
            if workspaces.workspaces.isEmpty {
                Text("No workspaces yet")
            } else {
                ForEach(workspaces.workspaces) { ws in
                    Button {
                        workspaces.selectAndTouch(ws.id)
                    } label: {
                        HStack {
                            Text(ws.displayName)
                            if ws.id == workspaces.selectedId {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                Divider()
            }
            Button("Add folder…") {
                _ = workspaces.pickAndAdd()
            }
            if let selected = workspaces.selected {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting(
                        [URL(fileURLWithPath: selected.path)]
                    )
                }
                Button("Close project…", role: .destructive) {
                    confirmClose = true
                }
            }
        } label: {
            SelectorChipLabel(
                systemImage: "folder.fill",
                title: workspaces.selected?.displayName ?? "Choose folder",
                detail: workspaces.selected?.shortPath
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(workspaces.selected?.path ?? "Select a workspace folder for this task")
        .accessibilityLabel(
            workspaces.selected.map { "Workspace \($0.displayName)" } ?? "Choose workspace folder"
        )
        .confirmationDialog(
            "Close this project?",
            isPresented: $confirmClose,
            titleVisibility: .visible
        ) {
            Button("Close project", role: .destructive) {
                if let path = workspaces.selected?.path {
                    workspaces.close(path: path)
                    workspaces.ensureSelection()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The project leaves the sidebar. Existing tasks stay under Recents.")
        }
    }
}

// MARK: - Harness selector

struct HarnessSelectorMenu: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if model.harnesses.isEmpty {
            SelectorChipLabel(
                systemImage: "cpu",
                title: "No harness",
                showsChevron: false
            )
            .help("No harness adapter configured yet")
            .accessibilityLabel("No harness adapter configured")
        } else {
            Menu {
                ForEach(model.harnesses) { harness in
                    Button {
                        model.selectHarness(harness.id)
                    } label: {
                        HStack {
                            Text(harness.name)
                            if harness.id == model.selectedHarnessId {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                SelectorChipLabel(
                    systemImage: "cpu",
                    title: model.selectedHarness?.name ?? "Choose harness"
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(
                model.selectedHarness.map { "Harness: \($0.name) (\($0.id))" }
                    ?? "Choose a harness adapter"
            )
            .accessibilityLabel(
                model.selectedHarness.map { "Harness \($0.name)" } ?? "Choose harness"
            )
        }
    }
}

// MARK: - Local environment (badge, not a fake menu)

struct LocalEnvironmentBadge: View {
    var body: some View {
        SelectorChipLabel(
            systemImage: "desktopcomputer",
            title: "Local",
            showsChevron: false
        )
        .help("Tasks run on this Mac. Remote environments are not available yet.")
        .accessibilityLabel("Environment: Local")
    }
}

// MARK: - Header chip (active session)

struct WorkspaceChip: View {
    let workspacePath: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(display)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .help(workspacePath)
        .accessibilityLabel("Workspace \(display)")
    }

    private var display: String {
        Workspace.displayPath(workspacePath)
    }
}
