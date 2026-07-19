# Wiring

```
App launches sidecar → WS+token
Orch: session mgr | policy | event log | artifacts | adapter host
Adapter: spawn harness, map I/O ↔ semantic events
Shell: platform host + projector (not harness host)
```

## Host contract (shell → orch)

Shell creates data dirs, starts the sidecar, reads endpoint+token, opens WS. Orch does not decide app lifecycle or Mac paths.

```
code-free-orch \
  --data-root <path> \
  --bind 127.0.0.1:0 \
  --token-file <path> \
  --log-dir <path>
```

Lifecycle v0: **hybrid**, shell-driven. Idle quit → SIGTERM sidecar (graceful: finish flush, stop children). Active turn → orch may keep running; shell reattaches on relaunch (orch exposes busy/status). Always shell policy, not a free-floating daemon.

Transport (WS now, UDS later) must not change event types.

**Host production rules:** loopback bind; token before any command; endpoint+token only via agreed channel (stdout once or token-file), never guessable fixed secrets.

## Rules

1. App never holds harness pid
2. Only orch writes event log (single writer; monotonic `seq` per session)
3. One active turn/session v0; multi-session OK
4. Paths on the wire are opaque strings — shell maps to reveal/open/Quick Look
5. Caps = agent surface (`streaming_text`, `approvals`, …), not OS features
6. App knows harness only via `harness.list` (id, name, caps) — no CLI/SDK imports in the shell
7. Persist before acking durability-sensitive work; reconnect never requires a fresh empty log

## Adapter

```
start/send/cancel/(approve) + capabilities[]
TaskSpec: sessionId, cwd, model?, policy, resumeToken?, extra?
EventSink.emit(semantic) / emitRaw?
Fidelity: structured > jsonl > pty(lossy)
```

## Flows (one-liners)

| | |
|--|--|
| New session | create → subscribe → snapshot |
| Send | message.user → start/send → deltas/tools → turn_end |
| Approval | approval.requested → policy or GUI → adapter.approve |
| Artifact | artifact.created/updated (adapter emit and/or Outputs FS watch → durable events) → shell open/reveal |
| Cancel | adapter.cancel → session.ended |
| Reconnect | subscribe afterSeq → gap fill; child keeps running |

## Project

Named project dir + default harness. Session cwd defaults to project dir (Codex-style); optional per-session override. Display name / recents / bookmarks are shell; orch stores cwd + session metadata. Worktrees backlog.

**Handoff (harness or context switch):** not mid-session mutation. Shell/orch runs a designed “summarize context + next tasks” turn on the current session, then `session.create` with that seed (and chosen harness). Full transcript dump is not the default seed.

## Failures

Missing binary / parse error / child crash / WS drop: surface event or resubscribe; don't kill transcript.

| Failure | Production behavior |
|---------|---------------------|
| WS drop | Resubscribe `afterSeq`; gap fill; harness keeps running |
| Bad frame / auth | Close or `error`; do not partially apply |
| Child crash | `session.error` (or equivalent); log preserved; user can start new turn/session |
| Missing harness binary | Clear error event + UI; no hang |
| Orch crash | Shell restarts sidecar; history from SQLite; in-flight turn may be incomplete but prior seq intact |
