import SwiftUI

// MARK: - Home / orchestrator (Codex-style empty state)

/// Centered new-task surface: greeting, composer, workspace + harness + environment selectors.
struct NewTaskHomeView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var workspaces: WorkspaceStore
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            VStack(spacing: 28) {
                greeting
                homeComposer
                    .frame(maxWidth: 640)
                selectors
            }
            .padding(.horizontal, 32)

            Spacer(minLength: 24)

            HStack {
                newProjectButton
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            workspaces.ensureSelection()
            focused = true
        }
    }

    private var greeting: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 52, height: 52)
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            Text("What are we doing today?")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
        }
    }

    private var homeComposer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Button {} label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.medium))
                        .frame(width: 28, height: 28)
                        .background(Color.primary.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(true)
                .help("Attachments — not available yet")

                TextField("Ask Anything", text: $model.composerText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .lineLimit(1...10)
                    .focused($focused)
                    .onSubmit {
                        if !NSEvent.modifierFlags.contains(.shift) {
                            model.startTaskFromHome()
                        }
                    }

                Button {
                    model.startTaskFromHome()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(canSend ? Color.white : Color.secondary)
                        .frame(width: 30, height: 30)
                        .background(
                            canSend ? Color.accentColor : Color.primary.opacity(0.08),
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .keyboardShortcut(.return, modifiers: [.command])
                .help("Start task (⌘↩)")
            }

            HStack(spacing: 8) {
                composerChip(title: "Add photos & files", systemImage: "photo.on.rectangle", enabled: false)
                composerChip(title: "Plan", systemImage: "list.bullet.rectangle", enabled: false)
                Spacer(minLength: 8)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 16, y: 6)
    }

    private func composerChip(title: String, systemImage: String, enabled: Bool) -> some View {
        Button {} label: {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.05), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .foregroundStyle(enabled ? .primary : .tertiary)
        .help(enabled ? title : "\(title) — not available yet")
    }

    private var selectors: some View {
        HStack(spacing: 10) {
            WorkspaceSelectorMenu()
            HarnessSelectorMenu()
            EnvironmentSelectorMenu()
        }
    }

    private var newProjectButton: some View {
        Button {
            model.newProject()
        } label: {
            Label("New project", systemImage: "folder.badge.plus")
                .font(.callout)
        }
        .buttonStyle(.borderless)
        .disabled(!isReady)
        .help("Add a workspace folder")
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

// MARK: - Workspace selector

/// Folder workspace picker under the home composer (`code-free /` style).
struct WorkspaceSelectorMenu: View {
    @EnvironmentObject private var workspaces: WorkspaceStore

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
                Button("Close project", role: .destructive) {
                    workspaces.close(path: selected.path)
                }
            }
        } label: {
            selectorLabel(
                systemImage: "folder.fill",
                title: workspaces.selected?.displayName ?? "Choose folder",
                detail: workspaces.selected?.shortPath
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(workspaces.selected?.path ?? "Select a workspace folder for this task")
    }

    private func selectorLabel(systemImage: String, title: String, detail: String?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.callout.weight(.medium))
                .lineLimit(1)
            if let detail, !detail.isEmpty, detail != title {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.05), in: Capsule())
        .overlay(
            Capsule().strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

// MARK: - Harness selector

/// Harness picker for new tasks (`harness.list`). Empty list is honest — no fake adapters.
struct HarnessSelectorMenu: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Menu {
            if model.harnesses.isEmpty {
                Text("No harness adapter configured")
                Text("Adapters land in a later phase")
                    .foregroundStyle(.secondary)
            } else {
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
            }
        } label: {
            selectorLabel(
                systemImage: "cpu",
                title: model.selectedHarness?.name
                    ?? (model.harnesses.isEmpty ? "No harness" : "Choose harness"),
                detail: nil
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(
            model.selectedHarness.map { "Harness: \($0.name) (\($0.id))" }
                ?? "No harness adapter configured yet"
        )
    }

    private func selectorLabel(systemImage: String, title: String, detail: String?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.callout.weight(.medium))
                .lineLimit(1)
            if let detail, !detail.isEmpty, detail != title {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.05), in: Capsule())
        .overlay(
            Capsule().strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

// MARK: - Environment (Local only v0)

/// Honest Local-only environment chip. Remote/cloud is not faked.
struct EnvironmentSelectorMenu: View {
    var body: some View {
        Menu {
            Button {} label: {
                HStack {
                    Text("Local")
                    Image(systemName: "checkmark")
                }
            }
            .disabled(true)
            Text("Cloud / remote — not available yet")
                .foregroundStyle(.secondary)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "desktopcomputer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Local")
                    .font(.callout.weight(.medium))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.05), in: Capsule())
            .overlay(
                Capsule().strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Tasks run on this Mac. Remote environments are not available yet.")
    }
}

// MARK: - Header chip (active session)

/// Compact workspace path chip for the task header (cwd is fixed per session).
struct WorkspaceChip: View {
    let workspacePath: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(display)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .help(workspacePath)
    }

    private var display: String {
        Workspace.displayPath(workspacePath)
    }
}
