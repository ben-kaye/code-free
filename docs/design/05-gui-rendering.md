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

## Rules

- No harness TUI in the shell
- **Transcript = reduce(events); live == history** — one projector for streaming and for reopen; “replay” means re-reduce the log, not re-run the agent or open a log browser
- Unknown event → skip/debug
- No harness SDKs/CLI templates in the app — protocol only
- Paths from events are opaque; native open/reveal stays here
- Connection loss, orch restart, and session errors are first-class UI — not console-only
- Disabled/missing caps look disabled; never pretend a harness can do what it cannot
- Shell may use platform idioms freely; it must not invent a second wire protocol

## Viewers

Platform `ArtifactViewer`: match artifact → view. Image default; domain packs via meta/path. (macOS: Swift type; other shells: same role.)

## Native

Platform chrome stays in the shell. On macOS: Finder reveal, Quick Look, Settings, menu bar, notifications, (later) Keychain. Sandbox off v0. These are shell reactions to protocol data — not orch commands or adapter caps. Other OS shells use the equivalent native affordances.

## Non-goals

Web shell as product · vendor branding · one shared multi-OS GUI abstraction as the product (Electron/Tauri/etc.) · shipping non-macOS shells in v0 · session “Replay” / time-travel / ops log viewer as product chrome

## Reference UI

./codex-reference.png

Support light and dark mode. Keep GUI code simple and professional.
