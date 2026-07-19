# Stack

| | Choice |
|--|--------|
| OS | macOS 14+ only (GUI) |
| GUI | SwiftUI `.app` — platform shell |
| Orch | Node 24+ (LTS), TS — platform-agnostic runtime |
| IPC | localhost WS + token (UDS later) |
| Store | SQLite in orch |
| Artifacts | filesystem under data root |
| Protocol | `packages/protocol` (zod) → JSON Schema; Swift Codable hand-rolled v0 |
| Ship | `.app` + Node sidecar |

## Production defaults

Scope can be small; defaults must be shippable, not “dev then harden.”

| Area | Production default |
|------|--------------------|
| Bind | `127.0.0.1` only (never `0.0.0.0` in v0) |
| Auth | Cryptographic token required on every WS; no anonymous localhost |
| Token file | Restrictive perms; not world-readable; not logged |
| Store | SQLite durable on disk under data root; WAL or equivalent safe defaults |
| Schema | Validate inbound/outbound at orch; fail closed on unknown *commands* |
| Process | Graceful SIGTERM; flush/close DB; no orphan harnesses on clean quit |
| Logs | Structured, rotate under log-dir; no tokens/raw secrets |
| Deps | Pin versions; prefer maintained mainstream libs |
| Ship path | Same architecture for dev and release (bundle Node is packaging, not a redesign) |

## Dependencies

Prefer well-maintained libraries; invent only product logic (sessions, adapter map, policy, projection).

| Concern | Prefer | Avoid reinventing |
|---------|--------|-------------------|
| Schema / validation | zod → JSON Schema export | Hand-rolled parsers, dual ad-hoc types |
| WS server (Node) | `ws` (or equivalent mainstream) | Custom TCP framing |
| WS client (Swift) | `URLSessionWebSocketTask` | Custom socket stack |
| SQLite | better-sqlite3 or drizzle/kysely over it | Homegrown file log as primary store |
| Process / spawn | Node `child_process` (+ thin wrapper only if needed) | Custom process supervisor frameworks |
| CLI flags | something like `util.parseArgs` / commander / cac | DIY argv |
| Tests / fixtures | vitest (or project standard) + recorded jsonl | One-off harness mocks with no replay |
| Swift UI / async | SwiftUI, Foundation, structured concurrency | Extra GUI frameworks for shell |

**Own:** event semantics, adapter boundary, policy, Outputs UX, harness mapping.  
**Borrow:** bytes on the wire, SQL, schema tooling, process I/O primitives.

v0 exception: Swift Codable hand-rolled from the shared schema (codegen if drift hurts) — still schema-driven, not a second invented protocol.

## Seams

Platform weight lives in the frontend. Three contracts only:

| Seam | Contract |
|------|----------|
| Shell ↔ orch | Host process + authenticated event protocol. No shared memory, no harness pids. |
| Orch ↔ adapter | `start/send/cancel/approve` + caps + `EventSink`. No UI. |
| Adapter ↔ harness | CLI-specific I/O; lossy tiers OK; never required on the wire. |

**Shell owns:** glass, windowing, menus, sidecar launch/kill, default paths, Finder/Quick Look/notifications, Keychain if any.

**Orch owns:** sessions, policy, event log, artifacts on disk, adapter host.

**Do not:** abstract a multi-OS GUI in v0; hardcode `~/Library/...` inside orch; put OS features in agent caps.

## Layout

```
apps/macos/           # Xcode SwiftUI (platform shell)
apps/orchestrator/    # Node (no Cocoa, no windowing)
packages/protocol/
packages/adapters-*
packages/store/
fixtures/adapters/
```

## Data root

Shell chooses and passes `--data-root` (and bind/token paths). Orch never assumes a Mac Library layout.

**macOS default (shell):** `~/Library/Application Support/code-free/` — db, token/endpoint, artifacts, logs, raw jsonl

## Rejected (primary)

Tauri/Electron shell · pure-Swift adapters v0 · MAS-first sandbox · platform plugins inside Node for Mac-only UI · custom IPC framing / homegrown DB when a mainstream lib fits

## Locked (see [07](./07-open-questions.md))

System Node 24 for dev; bundle Node in `.app` before share · sandbox off v0 · FS watch Outputs + explicit `artifact.*`
