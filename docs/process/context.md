# Context engineering — keeping the committed context lean

Conventions for the files agents read on every session (CLAUDE.md, `docs/`, `.claude/skills/`),
based on Anthropic's Claude-5-era context-engineering guidance: every always-loaded line rents
attention from every session, so it has to earn its place.

- **CLAUDE.md = purpose + gotchas only** — things an agent could *not* learn by reading the
  files it's about to work on. If a linked doc already says it, link it; don't restate it.
- **No fast-changing facts in any CLAUDE.md** — test counts, version numbers, phase/status
  annotations. They go stale silently and then read as truth.
- **Process and verification discipline lives in skills** (`.claude/skills/`) — loaded on
  demand (progressive disclosure), referenced from docs and CLAUDE.md, never restated there.
- **One home per instruction.** Every rule has exactly one canonical location; everywhere else
  links to it. A duplicated rule forks, and the copies drift apart.
- **Hard rules only for critical areas** (environment safety, security, merge authority).
  Everything else is a default plus judgment, not a MUST — rule walls get skimmed.
- **In-flight status belongs in the vault** (`Canon/Modules`, the work board), not in committed
  files — commits are forever, status is for now.
