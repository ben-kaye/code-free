# Phase 3 PR plan

Product exit criteria: [deliverables](../design/06-deliverables.md) (phase 3).

SwiftUI shell + sidecar host. Speaks protocol only; no harness imports. Works against Phase 1 orch (honest `no_adapter` on send) until Phase 2 adapter lands.

### PR 1: Xcode scaffold + chrome

- **Description:** `apps/macos` XcodeGen project, NavigationSplitView shell (sidebar / transcript / inspector placeholders), light+dark, bundle id `com.ben-kaye.code-free`. No orch yet.
- **Files/components affected:** `apps/macos/`, `docs/plan/phase-3.md`, root README
- **Dependencies:** None

### PR 2: Protocol Codable + OrchClient

- **Description:** Hand Codable wire models; `URLSessionWebSocketTask` client with hello auth, requestId RPC demux, snapshot/event/result handling.
- **Files/components affected:** `apps/macos/CodeFree/Protocol/`, `apps/macos/CodeFree/Net/`
- **Dependencies:** PR 1

### PR 3: OrchHost sidecar

- **Description:** Shell-owned data root under Application Support; spawn `code-free-orch` with bind/token/log; parse endpoint line; SIGTERM on idle quit.
- **Files/components affected:** `apps/macos/CodeFree/Host/`
- **Dependencies:** PR 2

### PR 4: Sessions + transcript + composer

- **Description:** list/create/subscribe/send; `TranscriptReducer` (live == replay); connection error UI; reopen history.
- **Files/components affected:** `apps/macos/CodeFree/State/`, Views wiring
- **Dependencies:** PR 2, PR 3

### PR 5: Polish + tests

- **Description:** reconnect afterSeq, reducer unit tests, README runbook, hybrid reattach if cheap.
- **Files/components affected:** tests, README
- **Dependencies:** PR 4
