# Contributing to Code Free

Thanks for considering a contribution. This project is early and actively evolving; thoughtful PRs and design feedback are welcome.

## Before you start

1. Read the product contracts under [`docs/design/`](./docs/design/README.md) — especially [vision](./docs/design/01-vision.md) and the [event protocol](./docs/design/04-event-protocol.md).
2. Skim [AGENTS.md](./AGENTS.md) for seams, naming, and the production bar.
3. Check open issues and existing PRs so work is not duplicated.

**Architecture or protocol changes** should land in design docs (or an issue that proposes the contract change) *before* a large implementation PR. Implementation order and phase tracking live under [`docs/plan/`](./docs/plan/README.md) — do not fold task checklists into design docs.

## Development setup

### Requirements

- Node.js **≥ 24** (see [`.nvmrc`](./.nvmrc))
- [pnpm](https://pnpm.io) 11+
- macOS 14+ with Xcode 15+ if you touch the SwiftUI shell
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) to regenerate the Xcode project after `project.yml` changes
- Optional: [Grok](https://grok.x.ai) CLI on `PATH` (or `CODE_FREE_GROK`) to exercise the live Grok Build adapter

### Install and verify

```bash
pnpm install
pnpm test
pnpm typecheck
```

### macOS app

```bash
cd apps/macos && xcodegen generate
open CodeFree.xcodeproj
```

The Xcode scheme sets `CODE_FREE_REPO_ROOT` so the app can spawn the orchestrator from the monorepo. See the [README](./README.md) for binary resolution order and sidecar layout.

## How we work

### Seams (do not blur them)

| Owner | Responsibility |
|-------|----------------|
| Platform shell | Native UI (v0: SwiftUI macOS), host lifecycle, platform data paths |
| Orchestrator | Sessions, WS, durable event log, adapter host |
| Adapters | Harness I/O only — map to/from the protocol |
| `packages/protocol` | Wire schema; design doc [04](./docs/design/04-event-protocol.md) stays aligned |

Each OS gets its own shell in a **native** UI framework; orch and protocol stay shared. The shell never imports a harness SDK. Adapters never own the event log. Boundaries validate (zod / Codable); interiors trust typed data. Do not land Electron/webview product shells or a cross-platform GUI abstraction without a design lock.

### Production bar

Shipped paths must be durable, loopback+token secure, validated at wire edges, observable on failure, recoverable (resubscribe / `session.error`), honest about missing caps, tested on the critical path, and versioned. See [vision → Production bar](./docs/design/01-vision.md).

### Tests and fixtures

- Prefer automated tests for protocol, store, and adapter mapping.
- Harness stream fixtures live under [`fixtures/adapters/`](./fixtures/README.md). Prefer recorded streams over live harness calls in CI.
- Do not land silent `catch` / empty fallbacks that hide faults.

### Secrets

Never log tokens, credential file contents, or raw secrets. Token files stay mode `0600`.

## Pull requests

1. **Small, focused PRs** beat large multi-seam drops. One seam or one user-visible behavior per PR when practical.
2. **Describe intent** — what must hold after the change, and which design doc (if any) it implements.
3. **Keep green** — `pnpm test` and `pnpm typecheck` should pass. For shell changes, build the `CodeFree` scheme.
4. **Design first for contract changes** — protocol fields, caps, ownership, or security defaults need a design update (or an issue locking the decision) so implementers and future adapters share one source of truth.
5. **No second wire protocol** — extend `packages/protocol` and keep Swift Codable in step; do not invent parallel message shapes in the app or adapters.

### Good first contribution areas

- Adapter fixtures and mapping tests
- Docs clarity (design, README, comments that state real constraints)
- Orchestrator error codes / recoverable paths
- Second harness adapter (once Phase 5 design is ready — do not invent a parallel app integration path)
- UI polish that respects caps (disable or label; never fake Approve)

### What we will push back on

- Fake feature parity or stub approval UX
- Binding the orchestrator beyond loopback in v0
- Unvalidated ad hoc JSON deep inside modules
- Prototype seams on the critical path (“dev token,” in-memory-only history, rewrite-later IPC)
- Mixing design contracts with PR checklists in `docs/design/`

## Reporting bugs

Open an issue with:

- What you expected vs what happened
- Repro steps (CLI orch smoke and/or app steps)
- Relevant log excerpts from the orch log dir (**redact tokens**)
- Versions: Node, macOS, Xcode if relevant, and whether `grok` (or another harness) was involved

## Security

Local IPC is loopback + token by design. If you believe you found a vulnerability (auth bypass, token leakage, unsafe bind, log of secrets), **do not** open a public issue with exploit detail. Contact the maintainers privately (repository owner) first.

## License

By contributing, you agree that your contributions are licensed under the [MIT License](./LICENSE).
