# The dev ritual — working inside our parachute

Parachute development runs on its own Parachute. The **parachute-parachute team vault** (MCP alias `parachute-parachute`; `our.parachute.computer`) is the team brain **and the project-management system**: cross-repo `work` items (the vault is the source of truth for work — GitHub holds code + PRs), `decision` records, `meeting` digests, `capture/feedback` → `feedback-theme`, the `person` roster. Work spans repos via `repo/<slug>` tags. A weave job digests captures into `proposal` notes; **AI proposes, humans govern**.

## Every session with vault access

1. **Orient** — read `Current/Parachute` + the in-progress work board. Multiple sessions share this workspace: check who has claimed a repo **before** working in it, and before restarting shared daemons (hub/vault).
2. **Claim** — before substantive work, create/update a `work` note: `assignee: <handle>` (`aaron`, `uni`, …), a `repo/<slug>` tag for every repo you'll touch, `status: in-progress`. Skip the Claim for read-only investigation under ~3 commands.
3. **Log** — append progress, decisions, and surprises to your work note as you go. **Sessions are the new meetings**: a decision Aaron makes in-session gets a `Decisions/<date>-<slug>` note in the same session; direction-setting gets a `Strategy/` note. **The vault is the brain** — no loose `DESIGN-*`/`STRATEGY-*` files at the workspace root (the pre-2026-07 backlog lives in `docs/historical/`).
4. **Release** — on finishing: `status: in-review` / `shipped` / `dropped`. The weave flags stale claims and repo collisions.

## The GitHub-issues boundary (settled 2026-07-01)

An arc a human would name lives in the vault (`work`); a fix a PR will close within days lives in a GitHub issue; the vault note's `gh_links` points down at issues/PRs, never syncs status. File-level side-discoveries during a PR stay `gh issue create` material; anything arc-shaped goes on the board.

## Without vault access (outside contributors)

None of this is required — the normal GitHub flow (issues, PRs, reviews) stands alone. Each repo's own CLAUDE.md + docs carry what you need to work in it.

## Where knowledge lives (the taxonomy, ratified 2026-07-03)

- **Team vault** — project truth: strategy, decisions, work arcs, meetings, feedback, the module registry (`Canon/Modules`), the system map (`Reference/Architecture`).
- **Per-repo docs** — "how THIS repo works": architecture, gotchas, the contracts that repo enforces. A clone must carry it.
- **This workspace** (`docs/` + `.claude/`) — cross-repo dev *process*, encoded as tooling where possible.
- **Auto-memory** — a staging area: a lesson lands there, then **graduates** to its real home (repo docs, vault, or a workspace skill). A memory entry two other people would need is misfiled.
