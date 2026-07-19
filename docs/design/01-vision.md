# Vision

**What:** Codex-class macOS shell; pluggable harnesses; we own rendering.

**Why:** GUIs fused to one agent. Want one glass, many workers, intercept I/O.

## Goals

- Harness-agnostic sessions
- GUI detached (never spawns harness)
- Semantic event stream + custom artifact viewers
- Replayable sessions (SQLite)
- Unified approvals/policy

## Non-goals (v0)

- Build our own agent
- MAS / hard sandbox
- Non-macOS GUI
- Cloud sync, multi-user, marketplace, scheduled jobs

## Principles

1. Event log = source of truth
2. Caps, not fake parity
3. Semantic + optional raw streams
4. Second adapter validates abstraction
5. Artifacts first-class (Outputs)

## Done when

Chat via harness A → Outputs + timing → reopen app, history lives → same shell, harness B.
