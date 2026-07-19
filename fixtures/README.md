# Fixtures

Test inputs only — **not** product session history and not a user-facing “replay” feature.

Product history is the orch SQLite event log (see [vision → Event log](../docs/design/01-vision.md)).

## Phase 2 — adapter streams

Recorded ACP update lines for mapper unit tests (no live network). Purpose: pin harness→semantic mapping against **CLI churn**.

```
fixtures/adapters/grok-build/
  message-stream.jsonl
  thinking.jsonl
  tools.jsonl
  plan.jsonl
```

Consumed by `@code-free/adapter-grok-build` tests (`map-update.test.ts`).

## Phase 1

Protocol parse, store durability, and orchestrator WS history/gap-fill are programmatic (vitest), not fixture files.
