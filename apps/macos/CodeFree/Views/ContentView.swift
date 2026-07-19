import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    /// Inspector hidden by default — it is empty until artifacts/sources exist.
    @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn

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
        .navigationTitle(model.windowTitle)
        .toolbar {
            ToolbarItem(placement: .principal) {
                connectionPill
            }
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 8) {
                    if case .failed = model.phase {
                        Button("Restart") { model.restart() }
                            .help("Restart the orchestrator")
                    }
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            columnVisibility = columnVisibility == .all ? .doubleColumn : .all
                        }
                    } label: {
                        Image(systemName: "sidebar.trailing")
                    }
                    .help(columnVisibility == .all ? "Hide inspector" : "Show inspector")
                    .accessibilityLabel(
                        columnVisibility == .all ? "Hide inspector" : "Show inspector"
                    )
                }
            }
        }
        .overlay(alignment: .top) {
            if let banner = model.banner {
                BannerView(
                    banner: banner,
                    onDismiss: { model.dismissBanner() },
                    onAction: { model.performBannerAction($0) }
                )
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.banner)
        .onChange(of: model.windowTitle) { _, title in
            NSApp.keyWindow?.title = title
        }
        .onAppear {
            NSApp.keyWindow?.title = model.windowTitle
        }
    }

    private var connectionPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(connectionColor)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(model.connectionLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.6), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Connection: \(model.connectionLabel)")
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
    let banner: UserBanner
    let onDismiss: () -> Void
    let onAction: (UserBanner.Action) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(accentColor)
                .accessibilityHidden(true)
            Text(banner.message)
                .font(.callout)
                .lineLimit(4)
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            if let action = banner.action, let label = banner.actionLabel {
                Button(label) { onAction(action) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(accentColor)
            }
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(4)
            }
            .buttonStyle(.borderless)
            .help("Dismiss")
            .accessibilityLabel("Dismiss")
        }
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: 520)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(
                topLeadingRadius: 10,
                bottomLeadingRadius: 10,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0,
                style: .continuous
            )
            .fill(accentColor)
            .frame(width: 3)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(accentColor.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(styleLabel): \(banner.message)")
    }

    private var styleLabel: String {
        switch banner.style {
        case .info: return "Notice"
        case .warning: return "Warning"
        case .error: return "Error"
        }
    }

    private var iconName: String {
        switch banner.style {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "exclamationmark.circle.fill"
        }
    }

    private var accentColor: Color {
        switch banner.style {
        case .info: return .accentColor
        case .warning: return .orange
        case .error: return .red
        }
    }
}
