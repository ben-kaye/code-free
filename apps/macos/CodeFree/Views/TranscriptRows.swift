import SwiftUI

struct TranscriptRow: View {
    let item: TranscriptItem
    @State private var thinkingExpanded = false

    var body: some View {
        switch item.kind {
        case .user:
            HStack {
                Spacer(minLength: 40)
                ChatMarkdownView(source: item.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        Color.accentColor.opacity(0.18),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("You: \(Self.a11ySummary(item.text))")

        case .assistant:
            VStack(alignment: .leading, spacing: 4) {
                Text("Assistant")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                ChatMarkdownView(source: item.text)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Assistant: \(Self.a11ySummary(item.text))")

        case .thinking:
            DisclosureGroup(isExpanded: $thinkingExpanded) {
                // Plain text — thinking streams are noisy for full markdown/math.
                Text(item.text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .italic()
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            } label: {
                Label(
                    thinkingExpanded ? "Thinking" : thinkingSummary,
                    systemImage: "brain"
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            }
            .onAppear {
                if !didInitThinking {
                    didInitThinking = true
                    thinkingExpanded = item.text.count < 280
                }
            }

        case .system:
            Text(item.text)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 4)

        case .error:
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text(item.text)
                    .textSelection(.enabled)
                    .font(.callout)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color.orange.opacity(0.12),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Error: \(Self.a11ySummary(item.text))")

        case .timing:
            Text(item.text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)

        case .tool:
            Label(item.text, systemImage: toolIcon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color.primary.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .accessibilityLabel("Tool: \(Self.a11ySummary(item.text))")

        case .debug:
            Text(item.text)
                .font(.caption2.monospaced())
                .foregroundStyle(.quaternary)
        }
    }

    @State private var didInitThinking = false

    private var thinkingSummary: String {
        Self.a11ySummary(item.text, limit: 48, empty: "Thinking")
    }

    private var toolIcon: String {
        if item.text.contains("· Failed") {
            return "exclamationmark.triangle"
        }
        if item.text.contains("· Done") {
            return "checkmark.circle"
        }
        return "wrench.and.screwdriver"
    }

    /// Compact label for VoiceOver — full text is still selectable in the row content.
    private static func a11ySummary(
        _ text: String,
        limit: Int = 160,
        empty: String = "Empty message"
    ) -> String {
        let compact = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if compact.isEmpty { return empty }
        if compact.count <= limit { return compact }
        return String(compact.prefix(limit)) + "…"
    }
}
