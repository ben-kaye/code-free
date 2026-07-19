# AGENTS.md

macOS SwiftUI shell + harness-agnostic Node orchestrator. Shell owns glass + platform/host; adapters own harness I/O; event log is truth. Prefer mature libs for infra; own product semantics. Production-ready from day one: thin scope, no prototype seams.

## Document discipline

Two layers. Do not mix them.

| Layer | Path | Contains | Does not contain |
|-------|------|----------|------------------|
| Design | [docs/design/](./docs/design/README.md) | Product intent, seams, protocol, UX rules, production bar, locked decisions, phase *exit criteria* | PR stacks, file lists, checkboxes, “done/WIP”, branch/PR numbers |
| Plan / tracking | [docs/plan/](./docs/plan/README.md) (and root `README` Status) | PR plans, implementation order, phase progress | New product invariants (those go in design first) |

**Design** is the durable contract. Prefer abstract wording: what must be true, who owns what, failure behavior, non-goals. Avoid “we will implement…” prose; write “the system does / must…” so docs age with the product, not the sprint.

**Plan** is disposable tracking. PR plans may list files, deps, and cut order. When a PR ships, update the plan (or mark done) — do **not** fold task checklists into design docs.

### Rules for agents

1. **Read design before changing architecture** — start at [docs/design/README.md](./docs/design/README.md).
2. **Design edits only when the product contract changes** (seam, protocol, principle, non-goal, locked decision). Not when a PR lands.
3. **Implementation work is planned under `docs/plan/`**, not by expanding design with file-level steps.
4. **Locked decisions** live in [docs/design/07-open-questions.md](./docs/design/07-open-questions.md) (Locked section). New product questions open there; resolve by locking, then reflecting the decision into the relevant design doc (`01`–`05`).
5. **Phases** (in deliverables) describe shippable product slices and exit bars. They are not a substitute for a PR plan.
6. **Status for humans** may live in root `README` (“Phase N in progress”). Keep it one line; details stay in plan docs.
7. **No second source of truth for wire/protocol** — `packages/protocol` + [04-event-protocol.md](./docs/design/04-event-protocol.md) stay aligned; design describes semantics, code owns validation.

### When in doubt

- If it would still be true after a rewrite of the PR plan → **design**.
- If it is only true for the next few commits → **plan**.

## Clarity rubrics

Clarity means the reader can see *what must hold* and *which seam owns it* — not more prose.

### Code (Code Free invariants)

1. **Boundaries validate; interior trusts typed data** — zod/Codable at wire edges; no re-parsing ad hoc JSON deep inside.
2. **Failures surface** — harness/WS/store faults become events, hard errors, or UI — never silent catch / empty fallback.
3. **One module, one seam** — shell owns platform paths/host; orch owns sessions/log; adapters own harness I/O. No shell path logic in orch; no harness imports in the app.
4. **No temporary seams on the critical path** — durable log, loopback+token, validated protocol. No “dev bind / rewrite later” for the same job.
5. **Honest caps** — missing ability is off or labeled; never fake Approve or parity UX.
6. **Names match design vocabulary** — `EventSink`, `afterSeq`, data root, caps, harness id — not parallel jargon for the same concept.
7. **Locality over purity** — prefer a straight-line path in one place over many tiny helpers that obscure ownership. Extract when a second caller or seam appears.
8. **Secrets stay out of logs** — tokens, raw credentials, token-file contents never logged.

### Comments

- **Write for:** ordering/durability (`seq` only after durable append), security, lossy adapter mapping, non-obvious protocol rules.
- **Skip:** restating names/types/control flow; narrating the diff; diary TODOs without a plan or locked decision.
- **Tone:** short, present tense, durable. Point at the contract (design doc or package) instead of re-deriving it in prose.

### Self-check

1. Does a comment (or name) add a **constraint**, or only noise?
2. Could this be **simpler** and still meet the production bar and design seams?
3. If this fails at runtime, does the **user or event stream** learn about it?
