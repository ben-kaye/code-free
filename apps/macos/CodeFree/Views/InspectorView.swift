import SwiftUI

struct InspectorView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                section(title: "Outputs") {
                    placeholder(
                        icon: "folder",
                        text: outputsCopy
                    )
                }
                section(title: "Sources") {
                    placeholder(
                        icon: "doc.text",
                        text: sourcesCopy
                    )
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.background)
        .navigationTitle("Inspector")
    }

    private var outputsCopy: String {
        if model.selectedSession == nil {
            return "Open a task to see harness outputs and artifacts."
        }
        if model.selectedSession?.isArchived == true {
            return "No artifacts for this archived task."
        }
        return "No artifacts yet. Files and results from the harness show up here."
    }

    private var sourcesCopy: String {
        if model.selectedSession == nil {
            return "Open a task to see attachments and sources."
        }
        return "No attachments yet."
    }

    private func section(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func placeholder(icon: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text(text)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.primary.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
    }
}
