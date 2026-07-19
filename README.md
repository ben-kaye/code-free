# Code Free

Bring your own harness GUI for the future of coding.

**Display name:** Code Free · **Domain:** code.ben-kaye.com · **Bundle id:** com.ben-kaye.code-free

macOS SwiftUI shell + harness-agnostic Node orchestrator. Design: [docs/design/README.md](./docs/design/README.md).

## Status

**Phase 1** (in progress): protocol + SQLite event log + localhost WebSocket orchestrator.

## Requirements

- Node.js **≥ 24** (see `.nvmrc`)
- [pnpm](https://pnpm.io) 11+

## Workspace

```
apps/orchestrator/     # Node sidecar (WS + sessions)
packages/protocol/     # zod wire schema
packages/store/        # SQLite event log
fixtures/              # adapter fixtures (Phase 2+)
docs/design/           # product design
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
3. `session.create` → `session.subscribe` → `session.send` (Phase 1 records the user message and emits honest `session.error` / no adapter)

SIGTERM flushes and closes the DB.

## Production defaults (v0)

| Area | Behavior |
|------|----------|
| Bind | Loopback only (`127.0.0.1` / `::1`) |
| Auth | Token required on `hello`; token file mode `0600` |
| Store | SQLite under `--data-root`; seq after durable append |
| Protocol | Validated at boundary; unknown **commands** rejected |

## License

Private / TBD.
