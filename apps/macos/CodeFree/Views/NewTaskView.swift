import SwiftUI

// MARK: - Home / orchestrator

/// Centered new-task surface, or full-pane recovery when the orchestrator is down.
struct NewTaskHomeView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var workspaces: WorkspaceStore
    @FocusState private var focused: Bool
    /// Brief pulse when the user tries to start without a workspace.
    @State private var highlightWorkspace = false

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
            Spacer(minLength: 24)

            VStack(spacing: 18) {
                greeting
                homeComposer
                    .frame(maxWidth: 560)
                selectors
                statusLine
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 24)

            Spacer(minLength: 24)
        }
        .onAppear {
            workspaces.ensureSelection()
            if isReady { focused = true }
        }
        .onChange(of: model.phase) { _, phase in
            if case .ready = phase {
                focused = true
            }
        }
    }

    private func failedPane(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("Local orchestrator unavailable")
                .font(.title2.weight(.semibold))
            Text(message.isEmpty ? "Could not start or reach the local orchestrator." : message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button("Restart orchestrator") {
                InteractionFeedback.click()
                model.restart()
            }
            .buttonStyle(SoftProminentButtonStyle())
            .keyboardShortcut("r", modifiers: [.command])
            .accessibilityLabel("Restart local orchestrator")
        }
        .padding(32)
        .accessibilityElement(children: .combine)
    }

    private var greeting: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 16, weight: .semibold))
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
                    .animation(.easeOut(duration: 0.2), value: subtitle)
            }
        }
        .padding(.bottom, 4)
    }

    private var subtitle: String? {
        if model.isSending {
            return "Starting task…"
        }
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
            onSend: startFromHome
        )
        .opacity(isReady ? 1 : 0.72)
        .allowsHitTesting(isReady && !model.isSending)
    }

    private var selectors: some View {
        HStack(spacing: 8) {
            WorkspaceSelectorMenu(emphasized: needsWorkspace || highlightWorkspace)
            HarnessSelectorMenu()
            // Honest local-only label — not a menu-looking chip.
            LocalEnvironmentBadge()
        }
        .padding(.top, 2)
        .opacity(model.isSending ? 0.55 : 1)
        .allowsHitTesting(!model.isSending)
        .animation(.easeOut(duration: 0.18), value: model.isSending)
        .animation(.easeOut(duration: 0.2), value: highlightWorkspace)
    }

    private var statusLine: some View {
        Group {
            if model.isSending {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Creating task and sending first message…")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                Text(hintCopy)
                    .font(.caption)
                    .foregroundStyle(.secondary.opacity(0.85))
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: model.isSending)
        .accessibilityElement(children: .combine)
    }

    private var hintCopy: String {
        if needsWorkspace {
            return "Choose a folder to enable start · ⌘↩ when ready"
        }
        return "⌘↩ to start · Return for newline"
    }

    private var isReady: Bool {
        if case .ready = model.phase { return true }
        return false
    }

    private var needsWorkspace: Bool {
        workspaces.selected == nil
    }

    private var hasDraft: Bool {
        !model.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Draft is ready — missing workspace still enables send so the click can open the folder picker.
    private var canSend: Bool {
        guard isReady else { return false }
        guard !model.isSending else { return false }
        return hasDraft
    }

    private func startFromHome() {
        guard isReady, !model.isSending else { return }
        guard hasDraft else { return }

        if needsWorkspace {
            // Pulse the folder chip, then open the picker — never a silent no-op.
            withAnimation(.easeInOut(duration: 0.15)) {
                highlightWorkspace = true
            }
            InteractionFeedback.click()
            if workspaces.pickAndAdd() != nil {
                withAnimation(.easeOut(duration: 0.15)) {
                    highlightWorkspace = false
                }
                InteractionFeedback.click()
                model.startTaskFromHome()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        highlightWorkspace = false
                    }
                }
            }
            return
        }

        InteractionFeedback.click()
        model.startTaskFromHome()
    }
}

// MARK: - Shared selector chip

struct SelectorChipLabel: View {
    let systemImage: String
    let title: String
    var detail: String? = nil
    var showsChevron: Bool = true
    /// Stronger border when the chip needs attention (e.g. missing workspace).
    var emphasized: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(emphasized ? Color.accentColor : Color.secondary)
                .accessibilityHidden(true)
            Text(title)
                .font(.callout)
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
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(
                    emphasized
                        ? Color.accentColor.opacity(0.12)
                        : Color.primary.opacity(0.06)
                )
        )
        .overlay(
            Capsule()
                .strokeBorder(
                    emphasized ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.06),
                    lineWidth: emphasized ? 1.25 : 1
                )
        )
        .animation(.easeInOut(duration: 0.18), value: emphasized)
    }
}

// MARK: - Workspace selector

struct WorkspaceSelectorMenu: View {
    @EnvironmentObject private var workspaces: WorkspaceStore
    @State private var confirmClose = false
    var emphasized: Bool = false

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
                detail: workspaces.selected?.shortPath,
                emphasized: emphasized || workspaces.selected == nil
            )
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(ChipButtonStyle(emphasized: emphasized || workspaces.selected == nil))
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

// MARK: - Harness + model selector

/// Popover: harness chips + model × thinking-level matrix (rows = models, columns = effort).
struct HarnessSelectorMenu: View {
    @EnvironmentObject private var model: AppModel
    @State private var isPresented = false

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
            Button {
                isPresented.toggle()
            } label: {
                SelectorChipLabel(
                    systemImage: "cpu",
                    title: model.harnessModelChipTitle,
                    detail: model.selectedModel == nil ? nil : model.selectedHarness?.name
                )
            }
            .buttonStyle(ChipButtonStyle())
            .fixedSize()
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                HarnessModelPickerPopover(isPresented: $isPresented)
                    .environmentObject(model)
            }
            .help(helpText)
            .accessibilityLabel(accessibilityText)
        }
    }

    private var helpText: String {
        var parts: [String] = []
        if let h = model.selectedHarness {
            parts.append("Harness: \(h.name)")
        }
        if let m = model.selectedModel {
            parts.append("Model: \(m.selectionLabel(effortId: model.selectedReasoningEffortId))")
        }
        return parts.isEmpty ? "Choose harness and model" : parts.joined(separator: " · ")
    }

    private var accessibilityText: String {
        helpText
    }
}

struct HarnessModelPickerPopover: View {
    @EnvironmentObject private var model: AppModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            harnessSection
            if model.selectedHarness?.supportsModelsList == true {
                Divider()
                modelMatrixSection
            } else if model.selectedHarness != nil {
                Text("This harness does not expose a model list.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(minWidth: matrixMinWidth, maxWidth: 420)
        // Re-query orch on open and when the harness chip changes — no sticky shell cache.
        .task(id: model.selectedHarnessId) {
            await model.refreshModelsCatalogAsync()
        }
    }

    private var matrixMinWidth: CGFloat {
        let cols = max(unionEffortColumns.count, 1)
        return min(420, max(260, 140 + CGFloat(cols) * 56))
    }

    // MARK: Harness

    private var harnessSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Harness")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            if model.harnesses.count == 1, let only = model.harnesses.first {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                    Text(only.name)
                        .font(.callout.weight(.medium))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Harness \(only.name)")
            } else {
                HStack(spacing: 6) {
                    ForEach(model.harnesses) { harness in
                        harnessChip(harness)
                    }
                }
            }
        }
    }

    private func harnessChip(_ harness: HarnessInfo) -> some View {
        let selected = harness.id == model.selectedHarnessId
        return Button {
            InteractionFeedback.click()
            model.selectHarness(harness.id)
        } label: {
            Text(harness.name)
                .font(.callout.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    selected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05),
                    in: Capsule()
                )
                .overlay(
                    Capsule().strokeBorder(
                        selected ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.08),
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(SelectableCellButtonStyle(isSelected: selected))
        .accessibilityLabel("Harness \(harness.name)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Model matrix

    /// Union of effort ids across listed models (stable order: first-seen, prefer low→high when known).
    private var unionEffortColumns: [ReasoningEffortInfo] {
        var seen = Set<String>()
        var cols: [ReasoningEffortInfo] = []
        for m in model.models {
            for e in m.efforts where !seen.contains(e.id) {
                seen.insert(e.id)
                cols.append(e)
            }
        }
        return Self.orderedEfforts(cols)
    }

    private var modelMatrixSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Model")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                if model.isLoadingModels, !model.models.isEmpty {
                    ProgressView()
                        .controlSize(.mini)
                        .accessibilityLabel("Refreshing models")
                }
            }

            if model.isLoadingModels && model.models.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading models…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Loading models")
            } else if model.models.isEmpty {
                Text("No models available")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if unionEffortColumns.isEmpty {
                // No thinking axis — simple model list
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.models) { m in
                        simpleModelRow(m)
                    }
                }
            } else {
                Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 6) {
                    GridRow {
                        Text("")
                            .frame(minWidth: 100, alignment: .leading)
                        ForEach(unionEffortColumns) { effort in
                            Text(effort.displayLabel)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 48, maxWidth: .infinity)
                                .multilineTextAlignment(.center)
                        }
                    }
                    ForEach(model.models) { m in
                        GridRow {
                            Text(m.displayName)
                                .font(.callout.weight(.medium))
                                .lineLimit(1)
                                .frame(minWidth: 100, alignment: .leading)
                                .help(m.id)
                            if m.supportsReasoning {
                                ForEach(unionEffortColumns) { effort in
                                    effortCell(model: m, effort: effort)
                                }
                            } else {
                                // Model without efforts: single select spanning first column, rest disabled.
                                modelOnlyCell(m)
                                ForEach(Array(unionEffortColumns.dropFirst())) { _ in
                                    Color.clear.frame(width: 28, height: 28)
                                }
                            }
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Model and thinking level")
            }
        }
    }

    private func simpleModelRow(_ m: ModelInfo) -> some View {
        let selected = m.id == model.selectedModelId
        return Button {
            InteractionFeedback.click()
            model.selectModel(m.id, effortId: nil)
            isPresented = false
        } label: {
            HStack {
                Text(m.displayName)
                    .font(.callout.weight(.medium))
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                selected ? Color.accentColor.opacity(0.14) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(SelectableCellButtonStyle(isSelected: selected))
        .accessibilityLabel("Model \(m.displayName)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func effortCell(model m: ModelInfo, effort: ReasoningEffortInfo) -> some View {
        let available = m.efforts.contains(where: { $0.id == effort.id })
        let selected =
            available
            && m.id == model.selectedModelId
            && model.selectedReasoningEffortId == effort.id
        return Button {
            guard available else { return }
            InteractionFeedback.click()
            model.selectModel(m.id, effortId: effort.id)
            isPresented = false
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Color.accentColor : Color.primary.opacity(available ? 0.06 : 0.02))
                if selected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                } else if available {
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1.5)
                        .frame(width: 12, height: 12)
                }
            }
            .frame(width: 28, height: 28)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(SelectableCellButtonStyle(isSelected: selected))
        .disabled(!available)
        .help(available ? "\(m.displayName) · \(effort.displayLabel)" : "Not available for \(m.displayName)")
        .accessibilityLabel("\(m.displayName), \(effort.displayLabel)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(available ? "Select model and thinking level" : "Unavailable")
    }

    private func modelOnlyCell(_ m: ModelInfo) -> some View {
        let selected = m.id == model.selectedModelId
        return Button {
            InteractionFeedback.click()
            model.selectModel(m.id, effortId: nil)
            isPresented = false
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Color.accentColor : Color.primary.opacity(0.06))
                if selected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                } else {
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1.5)
                        .frame(width: 12, height: 12)
                }
            }
            .frame(width: 28, height: 28)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(SelectableCellButtonStyle(isSelected: selected))
        .help(m.displayName)
        .accessibilityLabel("Model \(m.displayName)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Prefer low → medium → high when those ids appear; keep other efforts after, first-seen order.
    private static func orderedEfforts(_ cols: [ReasoningEffortInfo]) -> [ReasoningEffortInfo] {
        let rank: [String: Int] = ["low": 0, "medium": 1, "high": 2, "xhigh": 3, "max": 4]
        return cols.enumerated().sorted { a, b in
            let ra = rank[a.element.id.lowercased()] ?? (100 + a.offset)
            let rb = rank[b.element.id.lowercased()] ?? (100 + b.offset)
            return ra < rb
        }.map(\.element)
    }
}

// MARK: - Local environment (plain label — not a disabled-looking menu)

struct LocalEnvironmentBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "desktopcomputer")
                .font(.caption)
                .accessibilityHidden(true)
            Text("This Mac")
                .font(.caption)
        }
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 4)
        .help("Tasks run on this Mac. Remote environments are not available yet.")
        .accessibilityLabel("Environment: This Mac")
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
