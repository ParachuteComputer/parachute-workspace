# Parachute Computer — the workspace

The dev substrate for the Parachute ecosystem. Each module repo is its own git repo cloned under this directory; this repo carries the workspace-wide practices — this file, `docs/`, and `.claude/` (skills).

**The frame: three layers, two doors, one contract.** The product is the trinity — **Vault → Surface → Agent** (deepen L1, gradual L2, experimental L3) — delivered through two doors: **Hub** (self-hosted) and **Cloud** (hosted), both speaking one wire contract (REST/MCP/OAuth/portable-md). Canonical: the team vault's `Canon/Modules` (registry of record) + `Reference/Architecture` (the one-page map); ratified in `Decisions/2026-07-03-three-layers-two-doors-one-contract`.

## On entering — orient

Read `Current/Parachute` via the `parachute-parachute` MCP, then the work board (`query-notes { tag: "work", metadata: { status: { eq: "in-progress" } } }`) — what's shipped, what's in flight, and **who's working where right now** (multiple sessions share this workspace). **No vault access?** Skip this — GitHub issues + PRs stand alone.

## The repos — `Canon/Modules` in the team vault is the registry of record; in-flight status lives there, not here

| Repo | Role |
|---|---|
| [`parachute-vault`](./parachute-vault) | **L1 Vault** — knowledge graph + MCP/REST; owns its domain across both doors |
| [`parachute-surface`](./parachute-surface) | **L2 Surface** — UI host + reference surfaces (Notes) + surface SDK + build-on-push |
| [`parachute-agent`](./parachute-agent) | **L3 Agent** — vault-native agents + messaging gateway (:1941); experimental preview |
| [`parachute-hub`](./parachute-hub) | **Door: self-hosted** — OAuth issuer, catalog, CLI, supervisor (:1939) |
| [`parachute-cloud`](./parachute-cloud) | **Door: hosted** — identity worker + control plane + billing (Cloudflare Workers/D1/DO/R2) |
| [`parachute.computer`](./parachute.computer) | Public site + blog; teaches the ladder |
| [`parachute-brain`](./parachute-brain) | Internal team surface over the project vault (merge delegated) |
| [`parachute-scribe`](./parachute-scribe) | **DEPRECATED** |
| [`parachute-patterns`](./parachute-patterns) | **ARCHIVING** (`Decisions/2026-07-03-patterns-archive`) |
| everything else | exploration (`parachute-pebble` = L1 capture client, active side project) or graveyard — see `Canon/Modules` |

**Compatibility labels** (the old "committed-core" axis): vault + surface-client/surface-render have real users — keep compatible; hub + cloud are the shipped doors — standard care, migrations for operator-visible changes; agent, surface-host near-zero — breaking OK; scribe deprecated.

## Process — the gotchas (the linked docs own the detail)

- **Dev ritual: Orient → Claim → Log → Release** (read-only investigations under ~3 commands skip the Claim) — [docs/process/development.md](./docs/process/development.md). **The vault is the brain — no loose design/strategy files at the workspace root** (historical ones live in `docs/historical/`).
- **Across repos:** `cd` into the target repo before dispatch (or brief the agent to cd first — otherwise it reads this file instead of the repo's CLAUDE.md). **Concurrent PRs per repo are fine when disjoint** — and genuinely disjoint now that feature PRs don't touch the version line or CHANGELOG top, which used to collide on every single merge. Serialize only when two branches heavily rewrite the same file, because that merge is a design call, not a conflict. Single dev branch `ag-unforced-dev`; branch first, then edit. Verify subagent claims against ground truth (`git show`, `gh pr diff`) — especially negative findings. Every PR gets an independent review before merge — **and a branch can be reviewed before it's a PR**, so reviews parallelize even when merges don't: [.claude/skills/review-subagents/](./.claude/skills/review-subagents/SKILL.md). The rest of the dispatch discipline: [docs/process/orchestration.md](./docs/process/orchestration.md).
- **Governance:** no auto-merge — Aaron merges (brain excepted). **Feature PRs don't bump the version or touch CHANGELOG** — a release PR does, and merging it publishes (CI compares package.json against npm). Stack related PRs rather than opening them all against `main`; shared-line edits in every PR is what made every merge conflict every other open PR. The contracts check, migration files: [docs/process/governance.md](./docs/process/governance.md).

## Local dev

Modules run **bun-linked** from checkouts — `parachute start <svc>` follows the checked-out branch (short service names: `restart surface`, not `restart parachute-surface`). **A restart serves whatever the checkout currently has on disk, triggered by Aaron, a crash-respawn, or another session, not just you — so branch work in these repos belongs in a worktree, checkout restored to `main` when done** ([docs/process/orchestration.md](./docs/process/orchestration.md)). After merging a frontend bump: `bun run build` in the repo, then `parachute restart <svc>`. Post-merge sync: `git fetch && git pull --ff-only` in affected repos (skip repos with uncommitted work); pull `main` before starting any new work.

@docs/index.md
