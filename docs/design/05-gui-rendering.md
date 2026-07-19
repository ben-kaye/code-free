# GUI

SwiftUI. Codex IA, not pixel clone. **Platform shell:** glass + native OS + sidecar host; not a thin webview over orch.

```
NavSplit: Projects/Recents | Transcript | Outputs+Sources inspectors
Composer: attach · approve policy · harness · model · send · handoff (new session seed)
```

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

- No harness TUI in glass
- Transcript = reduce(events); live == replay
- Unknown event → skip/debug
- No harness SDKs/CLI templates in the app — protocol only
- Paths from events are opaque; native open/reveal stays here
- Connection loss, orch restart, and session errors are first-class UI — not console-only
- Disabled/missing caps look disabled; never pretend a harness can do what it cannot

## Viewers

Swift `ArtifactViewer`: match artifact → view. Image default; domain packs via meta/path.

## Native

Finder reveal, Quick Look, Settings, menu bar, notifications, (later) Keychain. Sandbox off v0. These are shell reactions to protocol data — not orch commands or adapter caps.

## Non-goals

Web shell as product · vendor branding · multi-OS GUI abstraction in v0
