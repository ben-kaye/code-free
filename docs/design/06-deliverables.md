# Deliverables

**North star:** macOS app → chat harness → Outputs + timing → reopen history → second harness same shell.

**Quality bar:** every phase exit includes production-ready behavior for what it ships (durable log, auth’d IPC, validated protocol, tests/fixtures, recoverable failures). No “prototype then replace” on core seams. See [vision](./01-vision.md) production bar.

| Phase | Ship | Exit |
|------:|------|------|
| 0 | design docs | stack + first adapter agreed; production bar locked; [open questions](./07-open-questions.md) cleared |
| 1 | orch + protocol + sqlite + WS | replay after restart; token + loopback; schema validation; store/protocol tests |
| 2 | first adapter (**Grok Build**) | headless stream → semantic; cancel; fixtures; crash → session.error |
| 3 | SwiftUI shell + sidecar launch | full chat in `.app`; reopen history; reconnect UI; hybrid lifecycle (busy reattach) |
| 4 | Outputs, viewers, approvals | FS watch + events → Outputs; one custom viewer; approval path real or honestly capped |
| 5 | second adapter (Codex) + harness picker | no harness imports in app; caps drive UI; handoff → new session |
| 6 | plan/agent UI, polish, package | clean-account demo; release packaging (Node bundle) |

## Backlog

PTY tier · worktrees · multi-window · citations · schedule · remote orch · MAS

## Risks

| Risk | Mitigation (from day one) |
|------|---------------------------|
| CLI churn | Adapter fixtures / recorded streams |
| Approval gaps | Honest caps; never fake approve UX |
| Node bundle | Same orch binary path; packaging not redesign |
| Protocol drift | version + zod schema + tests; Codable or codegen |
| Data loss | SQLite single writer; seq after durable append |
| Local attack surface | loopback + token; no dev-only open bind |

## PR Plan

Phase 1 implementation stack. Later phases get their own plans.

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
