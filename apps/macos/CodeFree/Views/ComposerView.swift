import SwiftUI

/// Shared message composer for home and in-session.
/// Send is ⌘↩ only; Return inserts a newline in the multi-line field.
struct ComposerView: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var focused: Bool

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
                MessageComposerField(
                    text: $model.composerText,
                    placeholder: "Message",
                    canSend: canSend,
                    isSending: model.isSending,
                    focused: $focused,
                    onSend: { model.sendMessage() }
                )

                HStack {
                    Text("⌘↩ to send · Return for newline")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
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

    private var isArchived: Bool {
        model.selectedSession?.isArchived == true
    }

    private var canSend: Bool {
        guard case .ready = model.phase else { return false }
        guard model.selectedSessionId != nil else { return false }
        guard !isArchived else { return false }
        guard !model.isSending else { return false }
        return !model.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        HStack(alignment: .bottom, spacing: 10) {
            TextField(placeholder, text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .lineLimit(1...10)
                .focused(focused)
                .disabled(isSending)
                .accessibilityLabel(placeholder)
                .accessibilityHint("Press Command Return to send. Return inserts a new line.")

            Button(action: onSend) {
                ZStack {
                    if isSending {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 30, height: 30)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(canSend ? Color.white : Color.secondary)
                            .frame(width: 30, height: 30)
                            .background(
                                canSend ? Color.accentColor : Color.primary.opacity(0.08),
                                in: Circle()
                            )
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!canSend || isSending)
            .keyboardShortcut(.return, modifiers: [.command])
            .help("Send (⌘↩)")
            .accessibilityLabel(isSending ? "Sending" : "Send message")
            .accessibilityHint("Command Return")
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    focused.wrappedValue ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.10),
                    lineWidth: focused.wrappedValue ? 1.5 : 1
                )
        )
    }
}
