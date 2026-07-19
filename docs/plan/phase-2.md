# Phase 2 PR plan

Product exit criteria: [deliverables](../design/06-deliverables.md) (phase 2).

First harness adapter (**Grok Build**) via ACP stdio. Headless stream → semantic events; cancel; fixtures; crash → `session.error`.

### PR 1: adapter-core contract

- **Description:** Shared orch↔adapter types: `EventSink`, `TaskSpec`, `HarnessAdapter`, `AdapterRun`, `ModelInfo`, `AdapterError`. Depends on protocol `Cap` / `EventDraft` only.
- **Files/components affected:** `packages/adapter-core/`, root build graph, vitest aliases
- **Dependencies:** None (protocol already shipped)

### PR 2: Grok Build adapter + fixtures

- **Description:** Spawn `grok agent stdio`; JSON-RPC NDJSON client; map ACP `session/update` → drafts; cancel; binary resolve (`CODE_FREE_GROK` → PATH); fixtures + mapper/client tests. Export factory (no orch wire in isolation).
- **Files/components affected:** `packages/adapter-grok-build/`, `fixtures/adapters/grok-build/`
- **Dependencies:** PR 1

### PR 3: Adapter host in orchestrator

- **Description:** Host registry, session run map, replace `no_adapter` when harness present, cancel/approve/`harness.list`/`models.list`, dispose on SIGTERM/close. Integration tests with mock adapter.
- **Files/components affected:** `apps/orchestrator/src/` (`adapter-host.ts`, `sessions.ts`, `server.ts`, tests)
- **Dependencies:** PR 1, PR 2

### PR 4: Plan + README + smoke

- **Description:** This file, README status/runbook, fixtures README. Ensure `pnpm test` / `typecheck` green.
- **Files/components affected:** `docs/plan/`, `README.md`, `fixtures/README.md`
- **Dependencies:** PR 3

## Integration notes

- Transport: `grok agent [--model M] stdio` (ACP), not one-shot `grok -p`.
- Binary: `CODE_FREE_GROK` → `PATH` → well-known (`~/.grok/bin/grok`, `~/.local/bin/grok`) for GUI PATH.
- One child process per Code Free session; one active turn per session.
- Default `harnessId` on create: first registered adapter (`grok-build` in production).
- Live Grok smoke (optional): install/auth `grok`, run orch + shell, send a prompt.
