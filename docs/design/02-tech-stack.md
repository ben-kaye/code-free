# Stack

| | Choice |
|--|--------|
| OS | macOS 14+ only (GUI) |
| GUI | SwiftUI `.app` |
| Orch | Node 22+, TS |
| IPC | localhost WS + token (UDS later) |
| Store | SQLite in orch |
| Artifacts | filesystem under data root |
| Protocol | `packages/protocol` (zod) → JSON Schema; Swift Codable hand-rolled v0 |
| Ship | `.app` + Node sidecar |

## Layout

```
apps/macos/           # Xcode SwiftUI
apps/orchestrator/    # Node
packages/protocol/
packages/adapters-*
packages/store/
fixtures/adapters/
```

## Data root

`~/Library/Application Support/code-free/` — db, token/endpoint, artifacts, logs, raw jsonl

## Rejected (primary)

Tauri/Electron shell · pure-Swift adapters v0 · MAS-first sandbox

## Open

Bundle Node vs system Node · sandbox off (default) · see [07](./07-open-questions.md)
