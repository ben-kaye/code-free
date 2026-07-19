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
