# Phase 3 PR plan

Product exit criteria: [deliverables](../design/06-deliverables.md) (phase 3).

**Status: complete** — SwiftUI shell + sidecar; full chat; reopen history; reconnect `afterSeq`; hybrid busy reattach.

SwiftUI shell + sidecar host. Speaks protocol only; no harness imports.

### PR 1: Xcode scaffold + chrome

- **Description:** `apps/macos` XcodeGen project, NavigationSplitView shell (sidebar / transcript / inspector placeholders), light+dark, bundle id `com.ben-kaye.code-free`. No orch yet.
- **Files/components affected:** `apps/macos/`, `docs/plan/phase-3.md`, root README
- **Dependencies:** None
- **Status:** done

### PR 2: Protocol Codable + OrchClient

- **Description:** Hand Codable wire models; `URLSessionWebSocketTask` client with hello auth, requestId RPC demux, snapshot/event/result handling.
- **Files/components affected:** `apps/macos/CodeFree/Protocol/`, `apps/macos/CodeFree/Net/`
- **Dependencies:** PR 1
- **Status:** done

### PR 3: OrchHost sidecar

- **Description:** Shell-owned data root under Application Support; spawn `code-free-orch` with bind/token/log; parse endpoint line; SIGTERM on idle quit.
- **Files/components affected:** `apps/macos/CodeFree/Host/`
- **Dependencies:** PR 2
- **Status:** done

### PR 4: Sessions + transcript + composer

- **Description:** list/create/subscribe/send; `TranscriptReducer` (live == history reduce); connection error UI; reopen history.
- **Files/components affected:** `apps/macos/CodeFree/State/`, Views wiring
- **Dependencies:** PR 2, PR 3
- **Status:** done

### PR 5: Polish + tests

- **Description:** reconnect afterSeq, reducer unit tests, README runbook, hybrid reattach (busy quit leaves orch; relaunch reattaches via endpoint+pid).
- **Files/components affected:** tests, README, `OrchHost`, `AppModel`
- **Dependencies:** PR 4
- **Status:** done

## Exit checklist

| Criterion | How |
|-----------|-----|
| Full chat in `.app` | Shell → orch → adapter; composer send streams events |
| Reopen history | SQLite event log; select session → snapshot → same reduce as live (not re-run agent) |
| Reconnect UI | WS drop → auto reconnect + `subscribe(afterSeq:)` gap fill |
| Hybrid lifecycle | Idle quit SIGTERM; busy quit leave process; next launch TCP probe + reattach |
