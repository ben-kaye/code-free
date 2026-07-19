# Code Free

Bring your own harness GUI for the future of coding.

**Display name:** Code Free · **Domain:** code.ben-kaye.com · **Bundle id:** com.ben-kaye.code-free

macOS SwiftUI shell + harness-agnostic Node orchestrator. Design: [docs/design/README.md](./docs/design/README.md).

## Status

**Phase 2** (in progress): Grok Build adapter (`packages/adapter-grok-build`) + orch adapter host. With `grok` on `PATH` (or `CODE_FREE_GROK`), create session → send streams semantic events. Phase 3 shell already speaks protocol only and will pick up harness.list / streamed turns.

## Requirements

- Node.js **≥ 24** (see `.nvmrc`)
- [pnpm](https://pnpm.io) 11+
- Xcode 15+ (macOS app), [XcodeGen](https://github.com/yonaskolb/XcodeGen) to regenerate the project

## Workspace

```
apps/macos/                 # SwiftUI shell (Xcode / XcodeGen)
apps/orchestrator/          # Node sidecar (WS + sessions + adapter host)
packages/protocol/          # zod wire schema
packages/adapter-core/      # orch ↔ adapter contract
packages/adapter-grok-build/# Grok Build ACP adapter
packages/store/             # SQLite event log
fixtures/adapters/          # recorded ACP streams for tests
docs/design/                # product design (contracts)
docs/plan/                  # implementation PR plans
```

## Setup

```bash
pnpm install
pnpm test
pnpm typecheck
```

## Run orchestrator (manual smoke)

```bash
ROOT=$(mktemp -d)
pnpm --filter @code-free/orchestrator exec tsx src/cli.ts \
  --data-root "$ROOT/data" \
  --token-file "$ROOT/token" \
  --log-dir "$ROOT/logs" \
  --bind 127.0.0.1:0
```

Stdout prints one JSON line with `endpoint` and `tokenFile`. Connect with a WebSocket client:

1. Send `{"kind":"hello","protocolVersion":1,"token":"<token file contents>"}`
2. Expect server `hello`
3. `session.create` → `session.subscribe` → `session.send` (streams via Grok Build when `grok` is available; otherwise `session.error` with a clear code such as `binary_not_found`)

SIGTERM disposes harness children, flushes, and closes the DB.

### Optional: point at a specific Grok binary

```bash
export CODE_FREE_GROK=/path/to/grok
```

Resolution order: `CODE_FREE_GROK` → `PATH` → `~/.grok/bin/grok` → `~/.local/bin/grok`. The well-known paths cover the macOS app when launched from Xcode/Dock (minimal GUI `PATH`).

## Run macOS app

```bash
# once after clone / project.yml changes
cd apps/macos && xcodegen generate

# open in Xcode (scheme sets CODE_FREE_REPO_ROOT for orch discovery)
open CodeFree.xcodeproj

# or CLI build
xcodebuild -scheme CodeFree -project CodeFree.xcodeproj -configuration Debug -destination 'platform=macOS' build
```

The shell launches the Node orchestrator as a sidecar (`~/Library/Application Support/code-free/`). Dev resolution order for the orch binary:

1. `CODE_FREE_ORCH` (absolute path or shell command)
2. `CODE_FREE_REPO_ROOT` / discovered monorepo (`apps/orchestrator`)
3. `code-free-orch` on `PATH`

With Grok installed and authenticated, **home composer (or New task) → send** streams assistant deltas (and tools when the harness uses them). Without a binary, send still records the user message and surfaces a clear `session.error` (no hang). Quit idle → SIGTERM sidecar (disposes children); reopen → sessions and transcript replay from SQLite.

## Production defaults (v0)

| Area | Behavior |
|------|----------|
| Bind | Loopback only (`127.0.0.1` / `::1`) |
| Auth | Token required on `hello`; token file mode `0600` |
| Store | SQLite under `--data-root`; seq after durable append |
| Protocol | Validated at boundary; unknown **commands** rejected |

## License

Private / TBD.
