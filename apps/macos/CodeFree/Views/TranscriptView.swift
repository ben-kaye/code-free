import SwiftUI

struct TranscriptPane: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            if let session = model.selectedSession {
                header(session)
                Divider()
                transcriptList
                Divider()
                ComposerView()
            } else {
                emptyState
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func header(_ session: SessionSummary) -> some View {
        HStack {
            Text(session.displayTitle)
                .font(.headline)
                .lineLimit(1)
            Spacer()
            Text(session.cwd)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var transcriptList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(model.transcript) { item in
                        TranscriptRow(item: item)
                            .id(item.id)
                    }
                }
                .padding(20)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: model.transcript.count) { _, _ in
                if let last = model.transcript.last {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No session selected")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Start a new chat or pick one from Recents.")
                .font(.callout)
                .foregroundStyle(.tertiary)
            if case .ready = model.phase {
                Button("New chat") { model.newSession() }
                    .keyboardShortcut("n", modifiers: [.command])
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct TranscriptRow: View {
    let item: TranscriptItem

    var body: some View {
        switch item.kind {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(item.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.accentColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        case .assistant:
            Text(item.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .thinking:
            Text(item.text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .italic()
                .textSelection(.enabled)
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
                Text(item.text)
                    .textSelection(.enabled)
                    .font(.callout)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        case .timing:
            Text(item.text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        case .tool:
            Label(item.text, systemImage: "wrench.and.screwdriver")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(8)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        case .debug:
            Text(item.text)
                .font(.caption2.monospaced())
                .foregroundStyle(.quaternary)
        }
    }
}
