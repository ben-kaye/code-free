# Open

**None.** Phase-0 product/stack decisions are locked below. New questions go here as they appear.

## Locked

- Multi-doc design
- GUI → orch → adapter → harness
- SwiftUI macOS + Node orch + SQLite + WS
- Protocol v1 event log
- Platform in shell; orch OS-UI-agnostic; data root/bind/token passed by host
- Paths opaque on wire; caps = agent surface only
- Prefer ext libs for transport/schema/store/process; own product semantics only
- Production-ready from day one: thin scope, no prototype seams; durable/auth’d/validated/tested critical path
- JS: pnpm + **Node 24 LTS** (`engines` ≥24; Active LTS as of lock; 26 when it is LTS is a later bump, not v0)
- Adapter develop order: **Grok Build → Codex → Claude Code** (first ship adapter = Grok Build)
- Name / identity: display **Code Free**; domain **code.ben-kaye.com**; bundle id **com.ben-kaye.code-free**
- Orch lifecycle: **hybrid** — app quit may leave orch running if a turn is active; shell owns reattach + “still running?” affordances; clean idle quit still SIGTERM orch
- Approvals: **spike + honest caps** — real `approval.*` path when harness supports; otherwise cap off (never fake Approve UX); full policy engine later
- Workdir: **project dir = default session cwd** (Codex-style); optional per-session override; git worktrees backlog (not required for v0)
- Models: **adapter `listModels` + static fallback**; `models_list` cap drives picker
- Artifacts: **FS watch of Outputs under data root from day one**, plus explicit `artifact.*` when the adapter knows; dedupe by path; watch is not a substitute for durable event log (create/update events still written when watch fires)
- Harness switch: **no mid-session harness mutation**. **Handoff** = designed prompt asking the current model for best-belief context + future tasks → spawn **new session** (optionally other harness) seeded with that summary only — not full transcript dump by default
- Bundle Node: **system Node 24 for dev**; **embed Node in `.app` before share / clean-account demo** (same orch entrypoint; packaging not redesign)
- Sandbox: **off v0** (MAS non-goal)
- Swift models: **hand Codable from protocol schema**; codegen only if drift hurts
