import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel

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
                model.newSession()
            } label: {
                Label("New chat", systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .disabled(!isReady)

            List(selection: Binding(
                get: { model.selectedSessionId },
                set: { model.selectSession($0) }
            )) {
                Section("Recents") {
                    if model.sessions.isEmpty {
                        Text(emptyLabel)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .listRowSeparator(.hidden)
                    } else {
                        ForEach(model.sessions) { session in
                            SessionRow(session: session)
                                .tag(session.id)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .background(.background)
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
            return "No chats yet"
        }
    }
}

struct SessionRow: View {
    let session: SessionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(session.displayTitle)
                .font(.body)
                .lineLimit(1)
            Text(session.cwd)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }
}
