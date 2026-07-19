# Fixtures

## Phase 2 — adapter streams

Recorded ACP update lines for mapper unit tests (no live network):

```
fixtures/adapters/grok-build/
  message-stream.jsonl
  thinking.jsonl
  tools.jsonl
  plan.jsonl
```

Consumed by `@code-free/adapter-grok-build` tests (`map-update.test.ts`).

## Phase 1

Protocol parse, store durability, and orchestrator WS replay are programmatic (vitest), not fixture files.
