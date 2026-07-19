# Phase 1 PR plan

Product exit criteria: [deliverables](../design/06-deliverables.md) (phase 1).

Orchestrator + protocol + SQLite + WS. Later phases get their own plans.

### PR 1: Monorepo scaffold

- **Description:** pnpm workspace, TypeScript base config, root scripts, engines.node >=24, package stubs for protocol/store/orchestrator. No product logic.
- **Files/components affected:** package.json, pnpm-workspace.yaml, tsconfig.base.json, vitest.config.ts, .gitignore, .nvmrc, apps/orchestrator/package.json, packages/protocol/package.json, packages/store/package.json, README.md
- **Dependencies:** None

### PR 2: Protocol package

- **Description:** Zod source of truth for protocol v1 — wire envelopes, event types, client commands, caps, protocolVersion. Unit tests for valid/invalid frames; unknown commands fail closed.
- **Files/components affected:** packages/protocol/
- **Dependencies:** PR 1

### PR 3: Store package

- **Description:** SQLite event log single writer — sessions, monotonic seq per session, afterSeq query, durable append before seq stamp. Restart/reopen tests.
- **Files/components affected:** packages/store/
- **Dependencies:** PR 2

### PR 4: Orchestrator WS + session surface

- **Description:** CLI entry code-free-orch, loopback bind, token-file auth, WS hello/snapshot/event, session create/list/subscribe/send/cancel (no adapter yet), SIGTERM flush. Integration test with temp data-root.
- **Files/components affected:** apps/orchestrator/
- **Dependencies:** PR 2, PR 3

### PR 5: Replay fixtures + root smoke

- **Description:** Root test/typecheck scripts, reconnect/replay coverage, README runbook for manual orch smoke.
- **Files/components affected:** fixtures/, README.md, package.json scripts, apps/orchestrator integration tests
- **Dependencies:** PR 4
