# GUI

**Native per platform.** Each OS ships its own shell in that platform’s primary UI framework. v0 shell is **SwiftUI on macOS**. Codex IA, not pixel clone.

**Platform shell:** native UI + OS integration + sidecar host — not a thin webview over orch, not a cross-platform toolkit skin.

```
NavSplit: Projects/Recents | Transcript | Outputs+Sources inspectors
Composer: attach · approve policy · harness · model · send · handoff (new session seed)
```

IA above is product shape; each shell maps it with native controls (NavigationSplitView, etc.).

## Bindings

| UI | events |
|----|--------|
| bubbles | message.* |
| timing | status.turn_end |
| tools | tool.* |
| plan/agents | plan.* / agent.* |
| Outputs | artifact.* |
| Sources | attachments v0 |
| Approve | approval.* + policy |

**Phase gate:** chat content rules and the reduce path for `message.*` / `thinking.*` / `tool.*` / session / timing are in force for the v0 shell. Plan, agent nest, Outputs/`ArtifactViewer`, and approval chrome land with their deliverable phases — the shell must not invent fake UI for missing events or caps. Unknown event types stay skip/debug until a binding exists.

## Rules

- No harness TUI in the shell
- **Transcript = reduce(events); live == history** — one projector for streaming and for reopen; “replay” means re-reduce the log, not re-run the agent or open a log browser
- Unknown event → skip/debug
- No harness SDKs/CLI templates in the app — protocol only
- Paths from events are opaque; native open/reveal stays here
- Connection loss, orch restart, and session errors are first-class UI — not console-only
- Disabled/missing caps look disabled; never pretend a harness can do what it cannot
- Shell may use platform idioms freely; it must not invent a second wire protocol

## Transcript rows

The shell projects event kinds to row chrome. Content rendering differs by kind:

| Kind | Content treatment |
|------|-------------------|
| User / assistant message | Chat content pipeline (markdown + math) below |
| Thinking | Plain text only — no markdown/math pipeline (streams are noisy; disclosure chrome is enough) |
| System / status | Plain caption-style text |
| Error / session fault | First-class error chrome; plain body text |
| Tool | Tool row rules (below) — not the markdown pipeline |

## Chat content (markdown + math)

Wire events stay **opaque text** (`message.*`). The shell alone parses for display. Orch and adapters never ship a rich-text or AST protocol.

### Ownership

| Owner | Responsibility |
|-------|----------------|
| Wire / log | Opaque UTF-8 text on `message.*` (and equivalent body fields) |
| Shell parser | Segment tree, stream-safe incompletes, `$` policy |
| Shell markdown | Prose spans only, after math/code segments are lifted |
| `MathRenderer` port | Typeset complete, gated LaTeX; last-good + raw fallback |
| Shell layout | Width-aware flow for mixed prose + inline math |

Math and markdown are **GUI concerns only** — not adapter-specific and not a second wire format.

### Parse before render

Segment tree **first**, then render. Do not regex math out of a finished attributed/markdown tree.

**Block order (outer):**

1. Fenced code (` ``` ` at line start)
2. Display math: `$$…$$` and `\[…\]`
3. Remaining text → prose **units** (below), each a stacked segment

**Prose units (block structure is a view tree):**

- Blank lines separate paragraphs; each paragraph is its own segment.
- Tight list rows (`1. ` / `1) ` / `- ` / `* ` / `+ `) become one segment each (markers stay in the text).
- Soft single newlines inside a non-list paragraph collapse to spaces (column reflow).
- Markdown attribution is **inline only** per unit. Do **not** use full markdown presentationIntent for paragraph/list layout — the character buffer drops block boundaries and a single `Text` smashes adjacent units.

**Inline order (within a prose unit):**

1. Backtick code spans (protect `$` and delimiters inside)
2. Inline math: `\(…\)` then `$…$`
3. Remainder → markdown prose spans

### Stream-safe incompletes

| Token | While unclosed | After close |
|-------|----------------|-------------|
| Code fence | Remainder of the message is an **open code block** (code chrome to EOF) — not math-typeset, not left as ambient prose | Closed fence → normal code block; following text resumes prose |
| Display / inline math delimiters | Stay **literal in prose** — never handed to the math backend | Closed → math segment; render only if the gate passes |

Incomplete tokens must not flash broken typesetting. Unclosed math is never “half-rendered.”

### Math render gate

Typeset only when the body is non-empty and **structurally** looks complete enough (brace / environment depth balanced; trailing incomplete control sequences rejected). This is a **heuristic**, not a guarantee that the backend accepts the LaTeX.

Policy after a closed, gated body:

1. Backend success → show typeset result; remember it as **last successful render** for that view.
2. Backend failure while a last-good exists → **keep last-good** (no flash of raw mid-edit / unsupported macro).
3. No successful render yet → **selectable raw LaTeX** only.

All math backends behind the port must honor this policy (native and any later KaTeX/web backend).

### `MathRenderer` port

The shell depends on a backend **abstraction**, not a concrete typesetter in call sites.

| v0 | Later (optional) |
|----|------------------|
| Native typesetter (e.g. SwiftMath) + selectable raw fallback | Alternate backend (e.g. KaTeX) behind the same port |

Not a webview **transcript** shell: an optional web math backend is a contained renderer, not the product UI.

### Streaming identity

Segment views use **content-stable ids** (fingerprint of segment content + occurrence index) so an unchanged equation or code block keeps view state while the message grows around it.

- **Stable when** content is unchanged (including complete equations that stay the same as later tokens append).
- **Remount when** segment content changes — correct; the body must re-typeset.
- Incomplete open math is not typeset; identity churn inside an unfinished region is acceptable because the gate holds raw/literal until ready.

### Layout

| Form | Layout |
|------|--------|
| Display math | Full transcript column width; centered block chrome |
| Inline math | Intrinsic size; participates in mixed flow with prose |
| Mixed prose + inline math | **Width-aware** reflow against the transcript column — not chip-measure at infinite width |
| Code blocks | Block chrome; monospaced body; full column width |

### `$…$` rules (currency-safe)

Inline dollars become math only when **all** hold:

- A closing `$` on the **same line**
- No leading or trailing whitespace inside the pair
- Not the start of `$$`
- Not inside a fenced code region or backtick span

Unclosed, space-padded, or multi-line `$…$` stays **literal**. Fenced code and `` `spans` `` protect `$`. Escaped dollars (`\$`) stay literal (not an open/close).

### Markdown surface (v0)

After segments are lifted, **prose spans** are rendered as platform markdown (best-effort). v0 requires a readable subset, not full GFM parity.

| In scope (must look intentional) | Best-effort / platform | Out of scope for bubble body |
|----------------------------------|------------------------|------------------------------|
| Emphasis, strong, strikethrough (if platform supports) | Tables, task lists, footnotes | Inline images as first-class artifact UI |
| Headings (scaled, not full page chrome) | Autolink edge cases | Embedding Outputs/artifacts inside the bubble |
| Lists, blockquotes | Deep nested HTML | Harness- or vendor-specific markup |
| Links (open with platform URL handler when valid) | — | A second rich-text wire format |
| Inline code (via markdown or protected spans) | — | Thinking-stream markdown (thinking is plain) |

Broken or partial markdown must degrade to readable text — never blank the bubble.

### Shell affordances (content)

- **Text selection** on prose, code, and raw LaTeX.
- **Copy LaTeX** for math segments (context menu or equivalent).
- **Toggle raw / typeset** when a successful render exists.
- **Accessibility:** math images expose a short label derived from the LaTeX source; rows keep sensible VoiceOver summaries.

## Tool rows

Separate from the markdown pipeline.

- Coalesce `tool.*` lifecycle by payload call **`id`** (not display name).
- Title/name is **label-only**; progress/done may omit title and keep the prior label.
- Missing or unknown tool fields must not invent a second identity scheme.

## Viewers

Platform `ArtifactViewer`: match artifact → view. Image default; domain packs via meta/path. (macOS: Swift type; other shells: same role.) Bubble markdown does not replace Outputs for binary or path-backed artifacts.

## Native

Platform chrome stays in the shell. On macOS: Finder reveal, Quick Look, Settings, menu bar, notifications, (later) Keychain. Sandbox off v0. These are shell reactions to protocol data — not orch commands or adapter caps. Other OS shells use the equivalent native affordances.

## Non-goals

Web shell as product · vendor branding · one shared multi-OS GUI abstraction as the product (Electron/Tauri/etc.) · shipping non-macOS shells in v0 · session “Replay” / time-travel / ops log viewer as product chrome · wire-level rich text or math AST · markdown pipeline on thinking streams · pixel-clone of any vendor chat UI

## Reference UI

./codex-reference.png

Support light and dark mode. Keep GUI code simple and professional.
