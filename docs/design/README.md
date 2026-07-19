# Design

Design docs are product contracts, not implementation trackers. PR plans live under [docs/plan/](../plan/README.md). Discipline: [AGENTS.md](../../AGENTS.md).

| # | Doc |
|---|-----|
| 1 | [vision](./01-vision.md) |
| 2 | [stack](./02-tech-stack.md) |
| 3 | [wiring](./03-wiring.md) |
| 4 | [protocol](./04-event-protocol.md) |
| 5 | [gui](./05-gui-rendering.md) |
| 6 | [deliverables](./06-deliverables.md) |
| 7 | [open](./07-open-questions.md) |

```
Native platform shell  →  Node orch  →  adapter  →  harness
 (SwiftUI macOS v0)        (shared)     (I/O map)
```

**Per-platform GUI:** each OS gets a shell in its native UI framework. Platform-specific behavior stays in the shell; orch/adapters speak protocol only. Seams: [stack](./02-tech-stack.md) · [wiring](./03-wiring.md) · [gui](./05-gui-rendering.md).

**Production-ready from day one** — narrow scope, durable design (no throwaway IPC/store/protocol). Bar: [vision](./01-vision.md).
