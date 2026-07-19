import SwiftUI

struct ComposerView: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 10) {
                // Caps not present yet — controls shown disabled, never fake approve
                Button {} label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .disabled(true)
                .help("Attachments — not available yet")

                TextField("Message", text: $model.composerText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...8)
                    .focused($focused)
                    .onSubmit {
                        if !NSEvent.modifierFlags.contains(.shift) {
                            model.sendMessage()
                        }
                    }

                Button {
                    model.sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.borderless)
                .disabled(!canSend)
                .keyboardShortcut(.return, modifiers: [.command])
                .help("Send (⌘↩)")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            HStack {
                Label("Approve", systemImage: "checkmark.shield")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("No harness adapter (Phase 1)")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .onAppear { focused = true }
    }

    private var canSend: Bool {
        guard case .ready = model.phase else { return false }
        guard model.selectedSessionId != nil else { return false }
        guard !model.isSending else { return false }
        return !model.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
