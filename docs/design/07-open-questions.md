# Open

**Proposed defaults — override freely.**

| ID | Q | Default |
|----|---|---------|
| 1 | First adapter | Claude; Codex second |
| 2 | JS pkg mgr | pnpm + Node 22 |
| 3 | Workdir | project cwd as-is |
| 4 | Orch lifecycle | die with app → later hybrid if tasks active |
| 5 | Approvals depth | spike; honest caps |
| 6 | Models | adapter listModels + static fallback |
| 7 | Artifacts | explicit events first; fs watch later |
| 8 | Mid-chat harness switch | new session only |
| 12 | Name / bundle id | TBD |
| 13 | Bundle Node? | system for dev; bundle before share |
| 14 | Sandbox | off v0 |
| 15 | Swift models | hand Codable; codegen if drift |

## Locked

- Multi-doc design
- GUI → orch → adapter → harness
- SwiftUI macOS + Node orch + SQLite + WS
- Protocol v1 event log
