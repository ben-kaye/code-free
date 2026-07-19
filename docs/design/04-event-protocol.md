# Protocol v1

Orch stamps `sessionId, seq, ts`. Adapters omit seq/ts.

**Transport:** standard WebSocket text frames, one JSON object per message (localhost + token). Do not invent a custom framing layer; UDS later keeps the same JSON envelopes.

**Schema:** `packages/protocol` (zod) is source of truth; export JSON Schema for docs/Swift. Message *shapes* are ours; parsing/validation/WS/SQLite are libraries.

**Production wire rules:** validate every client command; stamp `seq` only after durable append (or equivalent crash-safe ordering); unknown event *types* may be ignored by clients; unknown/invalid *commands* rejected; never break monotonic seq; `protocolVersion` negotiated on `hello`.

**Log vs transport:** the event stream is the durable product model (history + live). Snapshots and `afterSeq` gap fill re-deliver log rows; they do not re-execute the harness. `log` / `raw` event types are optional debug surface on the same channel — not a second history store.

## Server → client

`hello | snapshot | event | error`

**Event:** `{ protocolVersion, kind:"event", sessionId, seq, ts, type, payload }`

### Types

| type | notes |
|------|--------|
| session.started/ended/error | lifecycle |
| message.user / .delta / .done | group by message `id` |
| thinking.delta/done | optional |
| tool.started/progress/done/error | card |
| file.diff / file.write | edits |
| artifact.created/updated | Outputs |
| approval.requested/resolved | gates |
| plan.updated | steps[] |
| agent.started/progress/ended | nest via parentId |
| status / status.turn_start / status.turn_end | durationMs → “Worked for N s” |
| log / raw | debug |

Unknown types: ignore or generic card.

## Client → server

`hello | project.* | session.{list,create,archive,subscribe,unsubscribe,send,cancel,rename} | approval.respond | harness.list | models.list`

**Archive:** `session.archive` soft-deletes a session. `session.list` defaults to active sessions; `filter: "archived"` lists archives. Archived sessions are purged after **7 days** (orch on startup and after archive). Subscribe and history reduce remain allowed (read-only); send/rename/append are rejected.

## Caps

`streaming_text | tools | approvals | resume | subagents | mcp | artifacts | models_list`

## Extensibility

Prefer `artifact.meta` / `x.*` over core churn. Bump `protocolVersion` on breaks.
