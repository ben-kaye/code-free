# Vision

**What:** Codex-class **native** desktop shell per platform; pluggable harnesses; we own rendering.

**Why:** GUIs fused to one agent *and* to one cross-platform toolkit. Want one **native shell per OS**, many workers, intercept I/O.

## Goals

- Harness-agnostic sessions
- GUI detached (never spawns harness)
- **Per-platform shell** using that OS’s native UI framework (not a shared web/Electron UI)
- Semantic event stream + custom artifact viewers
- Replayable sessions (SQLite)
- Unified approvals/policy

## Non-goals (v0)

Narrow **scope**, not quality. Ship less surface; every shipped path is production-grade.

- Build our own agent
- MAS / hard sandbox
- **Ship** non-macOS shells (architecture allows later native shells; v0 is macOS only)
- Shared cross-platform GUI toolkit / webview-as-product shell
- Cloud sync, multi-user, marketplace, scheduled jobs

## Principles

1. **Production-ready from day one** — no prototype architecture, no “rewrite the seam later.” Thin product; durable design. (See bar below.)
2. Event log = source of truth
3. Caps, not fake parity
4. Semantic + optional raw streams
5. Second adapter validates abstraction
6. Artifacts first-class (Outputs)
7. **Platform-specific behavior lives in the shell** (native chrome, paths, host lifecycle); runtime is OS-UI-agnostic
8. Prefer mature external libs over bespoke infra (transport, schema, store, process)
9. **Native per platform** — each OS gets its own shell in the platform’s primary UI framework; orch/protocol stay shared; no lowest-common-denominator UI toolkit

### Production bar

Every design and implementation that ships must satisfy:

| Bar | Meaning |
|-----|---------|
| Durable | Restart / crash / kill does not corrupt the event log or strand the user without recovery |
| Secure (local) | Bind loopback only; token-gated IPC; secrets not in logs; data-root permissions sane |
| Validated | Protocol frames validated at boundaries (zod / Codable); reject garbage loudly |
| Observable | Structured logs; failures surface as events or UI, never silent |
| Recoverable | WS drop → resubscribe + gap fill; child crash → session.error; transcript preserved |
| Honest | Missing caps disabled or labeled — never fake parity |
| Tested | Fixtures + automated tests for protocol, store, adapters on the critical path |
| Versioned | `protocolVersion` + schema; breaking changes intentional |

**Not** production-ready: throwaway IPC, in-memory-only “history,” unbound ports, unvalidated JSON, “dev token,” ship-without-fixtures, or seams we plan to replace for the same job.

## Done when

Chat via harness A → Outputs + timing → reopen app, history lives → same **platform** shell, harness B — and the path above meets the production bar.
