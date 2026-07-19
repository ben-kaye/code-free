# Wiring

```
App launches sidecar → WS+token
Orch: session mgr | policy | event log | artifacts | adapter host
Adapter: spawn harness, map I/O ↔ semantic events
GUI: projector only
```

## Rules

1. App never holds harness pid
2. Only orch writes event log
3. One active turn/session v0; multi-session OK

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
| Artifact | artifact.created → Outputs |
| Cancel | adapter.cancel → session.ended |
| Reconnect | subscribe afterSeq → gap fill; child keeps running |

## Project

Named cwd + default harness. v0: harness runs in project cwd.

## Failures

Missing binary / parse error / child crash / WS drop: surface event or resubscribe; don't kill transcript.
