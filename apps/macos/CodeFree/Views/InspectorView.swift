import SwiftUI

struct InspectorView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                section(title: "Outputs") {
                    placeholder(
                        icon: "folder",
                        text: "Artifacts appear here when a harness emits them (Phase 4)."
                    )
                }
                section(title: "Sources") {
                    placeholder(
                        icon: "doc.text",
                        text: "Attachments and sources will list here."
                    )
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.background)
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
            Text(text)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
