import SwiftUI

struct TranscriptPane: View {
    @EnvironmentObject private var model: AppModel
    @State private var renameDraft = ""
    @State private var showingRename = false

    var body: some View {
        VStack(spacing: 0) {
            if let session = model.selectedSession {
                header(session)
                Divider()
                transcriptBody
                Divider()
                ComposerView()
            } else {
                NewTaskHomeView()
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .alert("Rename Task", isPresented: $showingRename) {
            TextField("Title", text: $renameDraft)
            Button("Save") {
                if let id = model.selectedSessionId {
                    model.renameSession(id, title: renameDraft)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose a short name for this task.")
        }
    }

    private func header(_ session: SessionSummary) -> some View {
        HStack(spacing: 12) {
            Button {
                renameDraft = session.title ?? session.displayTitle
                showingRename = true
            } label: {
                HStack(spacing: 6) {
                    Text(session.displayTitle)
                        .font(.headline)
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    if !session.isArchived {
                        Image(systemName: "pencil")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)
            .help(session.isArchived ? session.displayTitle : "Rename task")
            .accessibilityLabel(
                session.isArchived
                    ? "Task title, \(session.displayTitle)"
                    : "Task title, \(session.displayTitle). Click to rename."
            )
            .disabled(session.isArchived)

            if session.isArchived {
                Text("Archived")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.08), in: Capsule())
                    .foregroundStyle(.secondary)
                    .help("Archived tasks are permanently deleted after 7 days")
            }
            Spacer(minLength: 8)
            WorkspaceChip(workspacePath: session.cwd)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var transcriptBody: some View {
        if model.isLoadingTranscript {
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading conversation…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Loading conversation")
        } else if model.transcript.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                Text(
                    model.selectedSession?.isArchived == true
                        ? "No messages in this archived task"
                        : "No messages yet"
                )
                .font(.headline)
                .foregroundStyle(.secondary)
                if model.selectedSession?.isArchived != true {
                    Text("Describe what you need below. ⌘↩ to send.")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(32)
        } else {
            TranscriptScrollView()
        }
    }
}

// MARK: - Scroll + stick-to-bottom

struct TranscriptScrollView: View {
    @EnvironmentObject private var model: AppModel
    /// Follow the live end of the transcript unless the user scrolls away.
    @State private var stickToBottom = true
    @State private var showJumpToLatest = false
    /// Ignores bottom-sentinel disappear caused by our own scroll / content growth.
    @State private var ignoreBottomDisappear = false

    private let bottomID = "transcript-bottom"

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottom) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(model.transcript) { item in
                            TranscriptRow(item: item)
                                .id(item.id)
                        }
                        Color.clear
                            .frame(height: 1)
                            .id(bottomID)
                            .onAppear {
                                stickToBottom = true
                                showJumpToLatest = false
                            }
                            .onDisappear {
                                guard !ignoreBottomDisappear else { return }
                                stickToBottom = false
                            }
                    }
                    .padding(20)
                    .frame(maxWidth: 720, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: model.transcriptContentSignature) { _, _ in
                    if stickToBottom {
                        scrollToBottom(proxy: proxy, animated: true)
                    } else if !model.transcript.isEmpty {
                        showJumpToLatest = true
                    }
                }
                .onAppear {
                    scrollToBottom(proxy: proxy, animated: false)
                }

                if showJumpToLatest {
                    Button {
                        stickToBottom = true
                        showJumpToLatest = false
                        scrollToBottom(proxy: proxy, animated: true)
                    } label: {
                        Label("Jump to latest", systemImage: "arrow.down")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                            .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 12)
                    .accessibilityLabel("Jump to latest messages")
                }
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        ignoreBottomDisappear = true
        if animated {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo(bottomID, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(bottomID, anchor: .bottom)
        }
        stickToBottom = true
        // Content growth can fire onDisappear on the sentinel mid-stream; keep stickiness.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            ignoreBottomDisappear = false
            stickToBottom = true
        }
    }
}
