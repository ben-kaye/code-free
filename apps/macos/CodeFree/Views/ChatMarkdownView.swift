import SwiftUI

// MARK: - Markdown attribution (prose spans only — no math regex after the fact)

enum ChatMarkdownStyle {
    /// Inline markdown only. Block structure (paragraphs, lists) is a view tree from
    /// `ChatContentParser.splitProseUnits` — never presentationIntent on one Text.
    static func attributed(_ source: String) -> AttributedString {
        guard !source.isEmpty else { return AttributedString() }

        var options = AttributedString.MarkdownParsingOptions()
        // `.full` strips block boundaries from the character buffer; Text then smashes
        // paragraphs/list rows together. Units are already split; parse inline only.
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        options.failurePolicy = .returnPartiallyParsedIfPossible

        guard var attr = try? AttributedString(
            markdown: source,
            options: options,
            baseURL: nil
        ) else {
            return AttributedString(source)
        }

        for run in attr.runs {
            let range = run.range
            if let inline = run.inlinePresentationIntent, inline.contains(.code) {
                attr[range].font = .body.monospaced()
                attr[range].backgroundColor = Color.primary.opacity(0.08)
            }
        }
        return attr
    }
}

// MARK: - Chat body

/// Renders a chat message: parse → segments → views. Never math-regexes a finished AttributedString.
struct ChatMarkdownView: View {
    let source: String

    var body: some View {
        let blocks = ChatContentParser.parseIdentified(source)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(blocks) { block in
                switch block.content {
                case .prose(let inlines):
                    proseView(inlines)
                case .code(let language, let code):
                    CodeBlockView(language: language, code: code)
                case .displayMath(let latex):
                    DisplayMathView(latex: latex)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func proseView(_ inlines: [IdentifiedChatInline]) -> some View {
        if inlines.count == 1, case .markdown(let md) = inlines[0].inline {
            Text(ChatMarkdownStyle.attributed(md))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            // Width-aware flow: markdown subviews get a real width proposal so Text wraps.
            InlineFlowLayout(spacing: 4) {
                ForEach(inlines) { part in
                    switch part.inline {
                    case .markdown(let md):
                        Text(ChatMarkdownStyle.attributed(md))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    case .math(let latex):
                        InlineMathView(latex: latex)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Code fence

private struct CodeBlockView: View {
    let language: String?
    let code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let language, !language.isEmpty {
                Text(language)
                    .font(.caption2.weight(.medium).monospaced())
                    .foregroundStyle(.secondary)
            }
            Text(code)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            Color.primary.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }
}

// MARK: - Flow layout (markdown runs + inline math)

/// Lays out mixed `Text` + fixed-size math. Proposes remaining row width so markdown wraps
/// instead of measuring at infinite width (the previous atomic-chip bug).
private struct InlineFlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(maxWidth: proposal.width ?? .infinity, subviews: subviews, place: false)
        return result.size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        _ = layout(maxWidth: bounds.width, subviews: subviews, place: true, origin: bounds.origin)
    }

    /// Single walk for measure + place so wrapping decisions stay consistent.
    private func layout(
        maxWidth: CGFloat,
        subviews: Subviews,
        place: Bool,
        origin: CGPoint = .zero
    ) -> (size: CGSize, rows: [[(LayoutSubview, CGRect)]]) {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0
        var currentRow: [(LayoutSubview, CGRect)] = []
        var rows: [[(LayoutSubview, CGRect)]] = []

        func flushRow() {
            guard !currentRow.isEmpty else { return }
            if place {
                for (sub, rect) in currentRow {
                    let yOff = (rowHeight - rect.height) / 2
                    sub.place(
                        at: CGPoint(x: origin.x + rect.minX, y: origin.y + y + yOff),
                        proposal: ProposedViewSize(width: rect.width, height: rect.height)
                    )
                }
            }
            rows.append(currentRow)
            currentRow = []
            y += rowHeight + spacing
            x = 0
            rowHeight = 0
        }

        for sub in subviews {
            var size = measure(sub, maxWidth: maxWidth, x: x)
            if x > 0, maxWidth.isFinite, x + size.width > maxWidth + 0.5 {
                flushRow()
                size = measure(sub, maxWidth: maxWidth, x: 0)
            }
            let rect = CGRect(x: x, y: 0, width: size.width, height: size.height)
            currentRow.append((sub, rect))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            totalWidth = max(totalWidth, x - spacing)
            // Multi-line markdown that filled the column ends the row.
            if maxWidth.isFinite, size.width >= maxWidth - 0.5 {
                flushRow()
            }
        }
        if !currentRow.isEmpty {
            if place {
                for (sub, rect) in currentRow {
                    let yOff = (rowHeight - rect.height) / 2
                    sub.place(
                        at: CGPoint(x: origin.x + rect.minX, y: origin.y + y + yOff),
                        proposal: ProposedViewSize(width: rect.width, height: rect.height)
                    )
                }
            }
            rows.append(currentRow)
            y += rowHeight
        } else if y > 0 {
            y -= spacing
        }

        let width = maxWidth.isFinite ? maxWidth : totalWidth
        return (CGSize(width: width, height: max(0, y)), rows)
    }

    private func measure(_ sub: LayoutSubview, maxWidth: CGFloat, x: CGFloat) -> CGSize {
        if maxWidth.isFinite, maxWidth > 0 {
            let remaining = max(0, maxWidth - x)
            // Row start: full column width so Text wraps. Mid-row: remaining; rigid math keeps intrinsic size.
            let width = x <= 0 ? maxWidth : max(remaining, 1)
            let size = sub.sizeThatFits(ProposedViewSize(width: width, height: nil))
            return CGSize(width: min(size.width, maxWidth), height: size.height)
        }
        return sub.sizeThatFits(.unspecified)
    }
}
