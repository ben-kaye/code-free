import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    /// Inspector hidden by default — empty until the user opens it or has artifacts.
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
            // Healthy = quiet. Only show orch status while starting or failed.
            ToolbarItem(placement: .status) {
                connectionStatus
            }
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 8) {
                    if case .failed = model.phase {
                        Button("Restart") {
                            InteractionFeedback.click()
                            model.restart()
                        }
                        .help("Restart the local orchestrator")
                    }
                    Button {
                        InteractionFeedback.click()
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
        .onChange(of: model.selectedSessionId) { _, id in
            // Home / no session: collapse empty inspector so the composer owns the canvas.
            if id == nil, columnVisibility == .all {
                withAnimation(.easeInOut(duration: 0.15)) {
                    columnVisibility = .doubleColumn
                }
            }
        }
        .onAppear {
            NSApp.keyWindow?.title = model.windowTitle
        }
    }

    /// No capsule chrome. Hidden when ready — healthy state should not shout.
    @ViewBuilder
    private var connectionStatus: some View {
        switch model.phase {
        case .ready:
            EmptyView()
        case .starting, .idle:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                Text(model.connectionLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(model.connectionLabel)
        case .failed:
            HStack(spacing: 5) {
                Circle()
                    .fill(Color.red.opacity(0.9))
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
                Text(model.connectionLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(model.connectionLabel)
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
                Button(label) {
                    InteractionFeedback.click()
                    onAction(action)
                }
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
                    .padding(6)
                    .contentShape(Circle())
            }
            .buttonStyle(QuietButtonStyle(cornerRadius: 6, hoverOpacity: 0.08, pressedOpacity: 0.14))
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
