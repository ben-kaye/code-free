import SwiftUI

/// Shared message composer for home and in-session.
/// Send is ⌘↩ only; Return inserts a newline in the multi-line field.
struct ComposerView: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var focused: Bool

    /// Soft prompt-cache idle window used by several providers (not a hard SLA).
    private static let idleWarningSeconds: TimeInterval = 5 * 60

    var body: some View {
        VStack(spacing: 8) {
            if isArchived {
                Text("This task is archived. It will be permanently deleted after 7 days.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .accessibilityLabel("Archived task is read-only. Permanently deleted after 7 days.")
            } else {
                idleWarning

                MessageComposerField(
                    text: $model.composerText,
                    placeholder: "Message",
                    canSend: canSend,
                    isSending: model.isSending,
                    focused: $focused,
                    onSend: {
                        InteractionFeedback.click()
                        model.sendMessage()
                    }
                )

                HStack {
                    Text(hintText)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .animation(.easeOut(duration: 0.15), value: model.isSending)
                    Spacer()
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .onAppear {
            if !isArchived { focused = true }
        }
    }

    /// Show when the selected task has been idle ≥ 5 minutes (heuristic for cold prompt cache).
    @ViewBuilder
    private var idleWarning: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            if isIdle(at: context.date) {
                Text(
                    "Idle 5+ minutes — next reply may be slower or cost more while context is reprocessed."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
                .accessibilityLabel(
                    "Idle five or more minutes. Next reply may be slower or cost more while context is reprocessed."
                )
            }
        }
    }

    private var isArchived: Bool {
        model.selectedSession?.isArchived == true
    }

    private var hintText: String {
        if model.isSending {
            return "Sending…"
        }
        return "⌘↩ to send · Return for newline"
    }

    private var canSend: Bool {
        guard case .ready = model.phase else { return false }
        guard model.selectedSessionId != nil else { return false }
        guard !isArchived else { return false }
        guard !model.isSending else { return false }
        return !model.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func isIdle(at now: Date) -> Bool {
        guard !model.transcript.isEmpty, !model.isSending else { return false }
        guard let raw = model.selectedSession?.updatedAt, let last = Self.parseISO(raw) else {
            return false
        }
        return now.timeIntervalSince(last) >= Self.idleWarningSeconds
    }

    private static func parseISO(_ string: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: string) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: string)
    }
}

// MARK: - Shared field

struct MessageComposerField: View {
    @Binding var text: String
    var placeholder: String
    var canSend: Bool
    var isSending: Bool
    var focused: FocusState<Bool>.Binding
    var onSend: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            TextField(placeholder, text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .lineLimit(1...12)
                .focused(focused)
                .disabled(isSending)
                .opacity(isSending ? 0.65 : 1)
                .animation(.easeOut(duration: 0.15), value: isSending)
                .accessibilityLabel(placeholder)
                .accessibilityHint("Press Command Return to send. Return inserts a new line.")

            sendButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(borderColor, lineWidth: focused.wrappedValue ? 1.5 : 1)
        )
        .shadow(
            color: .black.opacity(focused.wrappedValue ? 0.08 : 0.04),
            radius: focused.wrappedValue ? 14 : 8,
            y: focused.wrappedValue ? 4 : 2
        )
        .animation(.easeOut(duration: 0.18), value: focused.wrappedValue)
        .animation(.easeOut(duration: 0.15), value: canSend)
    }

    private var borderColor: Color {
        if focused.wrappedValue {
            return Color.accentColor.opacity(0.50)
        }
        return Color.primary.opacity(0.10)
    }

    private var sendButton: some View {
        Button(action: onSend) {
            ZStack {
                Circle()
                    .fill(sendBackground)
                    .frame(width: 32, height: 32)

                if isSending {
                    ProgressView()
                        .controlSize(.small)
                        .tint(canSend || isSending ? Color.white.opacity(0.95) : Color.secondary)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(canSend ? Color.white : Color.secondary.opacity(0.85))
                }
            }
            .frame(width: 32, height: 32)
        }
        .buttonStyle(SendButtonStyle(isActive: canSend && !isSending))
        .disabled(!canSend || isSending)
        .keyboardShortcut(.return, modifiers: [.command])
        .help(isSending ? "Sending…" : "Send (⌘↩)")
        .accessibilityLabel(isSending ? "Sending" : "Send message")
        .accessibilityHint("Command Return")
        .animation(.easeInOut(duration: 0.18), value: canSend)
        .animation(.easeInOut(duration: 0.18), value: isSending)
    }

    private var sendBackground: Color {
        if isSending {
            return Color.accentColor.opacity(0.85)
        }
        if canSend {
            return Color.accentColor
        }
        return Color.primary.opacity(0.08)
    }
}
