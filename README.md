# Code Free

**Bring-your-own-harness GUI for agentic coding.**

Code Free is an MIT-licensed desktop shell that sits in front of your preferred
agent harness. v0 is macOS (SwiftUI); each platform gets its own native GUI.

Design contracts: [`docs/design/`](./docs/design/README.md) · Contributing: [`CONTRIBUTING.md`](./CONTRIBUTING.md)

## One shell, many harnesses

The shell should feel the same no matter which agent runs underneath. Harness
churn stays behind adapters. We prefer open interop (especially ACP) at the
harness edge so providers and clients can meet without fusing the GUI to one stack.

```
Native platform shell  →  Node orchestrator  →  adapter  →  harness / ACP agent
 (SwiftUI / macOS v0)       (sessions + log)     (I/O map)    (Grok, Codex via ACP, …)
```

- **Shell** — native UI for that OS, sidecar lifecycle, platform data paths.
  Never spawns a harness, never speaks ACP, never a webview over the orchestrator.
- **Orchestrator** — WebSocket IPC, sessions, durable event log, adapter host
  (OS-UI-agnostic). ACP only **via adapters** at the harness edge.
- **Adapters** — translate harness I/O (including **ACP**) into the shared
  semantic protocol. Generic ACP is the multi-harness path; ACP client I/O lives here.
- **Protocol** — versioned shell↔orch wire (`packages/protocol`); not ACP.

The **durable event log** is the source of truth: live stream and reopen share one reduce path (history, not a product “replay” mode). Missing harness abilities are **capped or labeled** — never faked. See [vision → Event log](./docs/design/01-vision.md).

## Features (current / direction)

| Area | Today | Direction |
|------|--------|-----------|
| Chat + stream | Grok Build via ACP when `grok` is available; honest `session.error` if not | Generic ACP adapter + second harness (e.g. Codex) same shell |
| History | SQLite event log; reopen task → same transcript as live | Outputs, viewers, real approvals (still log events) |
| Recovery | WS auto-reconnect + `afterSeq` gap-fill; hybrid busy reattach | Boring recovery; no log-browser UX |
| UI shell | SwiftUI macOS: projects, transcript, composer, harness/model pickers | Phase 4+ Outputs/approvals chrome |
| Security (local) | Loopback bind, token on `hello`, token file `0600` | Same bar for packaging / release |
| Caps | `harness.list` / `models.list` drive pickers; missing abilities not faked | Approvals UI only when cap on; full cap-driven surface |

## Requirements

- **Node.js ≥ 24** ([`.nvmrc`](./.nvmrc))
- **[pnpm](https://pnpm.io) 11+**
- **macOS 14+**, Xcode 15+, [XcodeGen](https://github.com/yonaskolb/XcodeGen) for the app
- Optional: **Grok** CLI on `PATH` or `CODE_FREE_GROK` for live adapter streams

## Quick start

```bash
pnpm install
pnpm test
pnpm typecheck
```

### Orchestrator (manual smoke)

```bash
ROOT=$(mktemp -d)
pnpm --filter @code-free/orchestrator exec tsx src/cli.ts \
  --data-root "$ROOT/data" \
  --token-file "$ROOT/token" \
  --log-dir "$ROOT/logs" \
  --bind 127.0.0.1:0
```

Stdout prints one JSON line with `endpoint` and `tokenFile`. With a WebSocket client:

1. Send `{"kind":"hello","protocolVersion":1,"token":"<token file contents>"}`
2. Expect server `hello`
3. `session.create` → `session.subscribe` → `session.send`

Streams via Grok Build when `grok` is available; otherwise `session.error` with a clear code (e.g. `binary_not_found`). SIGTERM disposes harness children, flushes, and closes the DB.

Optional binary override:

```bash
export CODE_FREE_GROK=/path/to/grok
```

Resolution order: `CODE_FREE_GROK` → `PATH` → `~/.grok/bin/grok` → `~/.local/bin/grok` (GUI apps often have a minimal `PATH`).

### macOS app

```bash
cd apps/macos && xcodegen generate
open CodeFree.xcodeproj
# or: xcodebuild -scheme CodeFree -project CodeFree.xcodeproj \
#        -configuration Debug -destination 'platform=macOS' build
```

The scheme sets `CODE_FREE_REPO_ROOT` for monorepo orch discovery. Data and token live under `~/Library/Application Support/code-free/`.

Orchestrator resolution: `CODE_FREE_ORCH` → monorepo `apps/orchestrator` → `code-free-orch` on `PATH`.

With Grok installed and authenticated, send from the home composer (or New task)
to stream assistant deltas and tools. Without a binary, the user message is still
recorded and a clear `session.error` surfaces — no hang.

**Lifecycle (hybrid)**
- Idle quit → SIGTERM sidecar
- Quit mid-turn → orch keeps running; next launch reattaches via saved endpoint
- WS drop → auto-reconnect + `subscribe(afterSeq:)` gap-fill (transcript kept)
- Reopen → re-reduce from the SQLite event log (same path as live)

## Repository layout

```
apps/macos/                  # Native SwiftUI shell (v0 platform GUI)
apps/orchestrator/           # Node sidecar (WS + sessions + adapter host)
packages/protocol/           # zod wire schema (shared source of truth)
packages/adapter-core/       # orch ↔ adapter contract
packages/adapter-grok-build/ # Grok Build specialized ACP adapter (fidelity / models / binary)
packages/adapter-acp/        # (planned) generic ACP: transport + default map
packages/store/              # SQLite event log
fixtures/adapters/           # recorded ACP streams for tests
docs/design/                 # product contracts (durable)
docs/plan/                   # implementation PR plans (disposable)
```

## Production defaults (v0)

| Area | Behavior |
|------|----------|
| Bind | Loopback only (`127.0.0.1` / `::1`) |
| Auth | Token required on `hello`; token file mode `0600` |
| Store | SQLite under `--data-root`; `seq` only after durable append |
| Protocol | Validated at boundary; unknown **commands** rejected |
| Failures | Surface as events, hard errors, or UI — never silent |

Full bar: [vision → Production bar](./docs/design/01-vision.md).

## Documentation

| Doc | Purpose |
|-----|---------|
| [docs/design/](./docs/design/README.md) | Product intent, seams, protocol, UX rules, phase exit criteria |
| [docs/plan/](./docs/plan/README.md) | PR plans and phase progress |
| [AGENTS.md](./AGENTS.md) | Seams, clarity rubrics, design vs plan discipline |
| [CONTRIBUTING.md](./CONTRIBUTING.md) | Setup, PR expectations, good first areas |
| [fixtures/](./fixtures/README.md) | Adapter stream fixtures |

## Contributing

Contributions are welcome under the MIT license.

- **Bugs and small fixes** — open an issue or PR; include repro steps and redacted logs.
- **Protocol / architecture** — propose the contract change in an issue or design doc update first.
- **New harness adapters** — implement against `packages/adapter-core` + protocol; do not wire harness SDKs into any platform shell.
- **New OS shells** — native UI framework for that platform + same host contract; design lock first (not Electron/webview by default).

See **[CONTRIBUTING.md](./CONTRIBUTING.md)** for setup, the production bar, and PR guidelines.

## Security

IPC is intentionally **local-only** (loopback + token). Report security issues privately to the repository owner rather than filing a public exploit write-up. Do not commit tokens or paste them into issues.

## License

[MIT](./LICENSE) © 2026 Ben Kaye
