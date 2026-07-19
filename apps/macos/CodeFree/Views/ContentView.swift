import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } content: {
            TranscriptPane()
                .navigationSplitViewColumnWidth(min: 360, ideal: 560)
        } detail: {
            InspectorView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 340)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                connectionPill
            }
            ToolbarItem(placement: .primaryAction) {
                if case .failed = model.phase {
                    Button("Restart") { model.restart() }
                }
            }
        }
        .overlay(alignment: .top) {
            if let banner = model.banner {
                BannerView(text: banner) {
                    model.banner = nil
                }
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.banner)
    }

    private var connectionPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(connectionColor)
                .frame(width: 7, height: 7)
            Text(model.connectionLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.6), in: Capsule())
    }

    private var connectionColor: Color {
        switch model.phase {
        case .ready:
            return .green
        case .starting, .idle:
            return .orange
        case .failed:
            return .red
        }
    }
}

struct BannerView: View {
    let text: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(text)
                .font(.callout)
                .lineLimit(3)
            Spacer(minLength: 8)
            Button("Dismiss", action: onDismiss)
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 520)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
    }
}
