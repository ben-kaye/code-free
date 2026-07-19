import AppKit
import SwiftMath
import SwiftUI

// MARK: - Port

/// Shell-local math backend. Wire protocol stays opaque text; only the GUI typesets.
@MainActor
protocol MathRenderer {
    /// Returns a view for complete, balanced LaTeX. Caller owns streaming / last-good policy.
    func makeView(latex: String, displayMode: Bool, fontSize: CGFloat) -> AnyView
}

/// Default stack: native SwiftMath, then selectable raw LaTeX.
@MainActor
enum MathRendering {
    static var shared: MathRenderer = NativeMathRenderer()
}

// MARK: - Native (SwiftMath ≈ KaTeX/MathJax for AppKit)

@MainActor
struct NativeMathRenderer: MathRenderer {
    func makeView(latex: String, displayMode: Bool, fontSize: CGFloat) -> AnyView {
        AnyView(
            NativeMathImageView(
                latex: latex,
                displayMode: displayMode,
                fontSize: fontSize
            )
        )
    }
}

/// Typesets via SwiftMath `MathImage` → `NSImage` (stable in LazyVStack; no per-row WKWebView).
private struct NativeMathImageView: View {
    let latex: String
    let displayMode: Bool
    let fontSize: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @State private var lastGood: LastGoodMath?
    @State private var showRaw = false

    var body: some View {
        Group {
            if let lastGood, !showRaw {
                Image(nsImage: lastGood.image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(
                        maxWidth: displayMode ? .infinity : nil,
                        alignment: displayMode ? .center : .leading
                    )
                    .accessibilityLabel("Math: \(lastGood.latex)")
            } else {
                RawMathFallback(latex: latex, displayMode: displayMode)
            }
        }
        .onAppear { resolve(latex) }
        .onChange(of: latex) { _, new in resolve(new) }
        .onChange(of: colorScheme) { _, _ in
            lastGood = nil
            resolve(latex)
        }
        .contextMenu {
            if lastGood != nil {
                Button(showRaw ? "Show rendered math" : "Show raw LaTeX") {
                    showRaw.toggle()
                }
            }
            Button("Copy LaTeX") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(latex, forType: .string)
            }
        }
    }

    private func resolve(_ source: String) {
        // Streaming gate: do not typeset incomplete structure; keep last good.
        guard MathBalance.mayRender(source) else {
            if lastGood == nil {
                showRaw = true
            }
            return
        }

        let color = NSColor.labelColor
        var mathImage = MathImage(
            latex: source,
            fontSize: fontSize,
            textColor: color,
            labelMode: displayMode ? .display : .text,
            textAlignment: displayMode ? .center : .left
        )
        let (error, image, _) = mathImage.asImage()
        if error == nil, let image, image.size.width > 0, image.size.height > 0 {
            lastGood = LastGoodMath(latex: source, image: image)
            showRaw = false
        } else if lastGood == nil {
            // No successful render yet → raw only.
            showRaw = true
        }
        // else: keep previous lastGood image (failed parse mid-edit / unsupported macro)
    }
}

private struct LastGoodMath {
    let latex: String
    let image: NSImage
}

// MARK: - Raw fallback

struct RawMathFallback: View {
    let latex: String
    let displayMode: Bool

    var body: some View {
        Text(displayMode ? "$$\(latex)$$" : "$\(latex)$")
            .font(.callout.monospaced())
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .frame(maxWidth: displayMode ? .infinity : nil, alignment: displayMode ? .center : .leading)
            .padding(displayMode ? 8 : 0)
            .accessibilityLabel("LaTeX: \(latex)")
    }
}

// MARK: - Public math views (policy + renderer)

struct DisplayMathView: View {
    let latex: String
    var fontSize: CGFloat = 17

    var body: some View {
        MathRendering.shared.makeView(latex: latex, displayMode: true, fontSize: fontSize)
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .background(
                Color.primary.opacity(0.04),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
    }
}

struct InlineMathView: View {
    let latex: String
    var fontSize: CGFloat = NSFont.preferredFont(forTextStyle: .body).pointSize

    var body: some View {
        MathRendering.shared.makeView(latex: latex, displayMode: false, fontSize: fontSize)
            .fixedSize()
    }
}
