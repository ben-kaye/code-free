# GUI

SwiftUI. Codex IA, not pixel clone.

```
NavSplit: Projects/Recents | Transcript | Outputs+Sources inspectors
Composer: attach · approve policy · harness · model · send
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

## Viewers

Swift `ArtifactViewer`: match artifact → view. Image default; domain packs via meta/path.

## Native

Finder reveal, Quick Look, Settings, menu bar. Sandbox off v0.

## Non-goals

Web shell as product · vendor branding
