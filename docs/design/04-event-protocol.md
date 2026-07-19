# Protocol v1

Orch stamps `sessionId, seq, ts`. Adapters omit seq/ts.

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

`hello | project.* | session.{list,create,subscribe,unsubscribe,send,cancel,rename} | approval.respond | harness.list | models.list`

## Caps

`streaming_text | tools | approvals | resume | subagents | mcp | artifacts | models_list`

## Extensibility

Prefer `artifact.meta` / `x.*` over core churn. Bump `protocolVersion` on breaks.
