# Parachute Computer — the workspace

The dev substrate for the Parachute ecosystem. Each module repo is its own git repo cloned under this directory; this repo carries the workspace-wide practices — this file, `docs/`, and `.claude/` (agents + skills).

**The frame: three layers, two doors, one contract.** The product is the trinity — **Vault → Surface → Agent** (deepen L1, gradual L2, experimental L3) — delivered through two doors: **Hub** (self-hosted) and **Cloud** (hosted), both speaking one wire contract (REST/MCP/OAuth/portable-md). Canonical: the team vault's `Canon/Modules` (registry of record) + `Reference/Architecture` (the one-page map); ratified in `Decisions/2026-07-03-three-layers-two-doors-one-contract`.

## On entering — orient

Read `Current/Parachute` via the `parachute-parachute` MCP, then the work board (`query-notes { tag: "work", metadata: { status: { eq: "in-progress" } } }`) — what's shipped, what's in flight, and **who's working where right now** (multiple sessions share this workspace). **No vault access?** Skip this — GitHub issues + PRs stand alone.

## The repos (one line each — `Canon/Modules` in the team vault is the registry of record)

| Repo | Role |
|---|---|
| [`parachute-vault`](./parachute-vault) | **L1 Vault** — knowledge graph + MCP/REST; transcription folding in (scribe-fold); owns its domain across both doors |
| [`parachute-surface`](./parachute-surface) | **L2 Surface** — UI host + reference surfaces (Notes) + surface SDK + build-on-push |
| [`parachute-agent`](./parachute-agent) | **L3 Agent** — vault-native agents + messaging gateway (:1941); experimental preview |
| [`parachute-hub`](./parachute-hub) | **Door: self-hosted** — OAuth issuer, catalog, CLI, supervisor (:1939) |
| [`parachute-cloud`](./parachute-cloud) | **Door: hosted** — identity worker + control plane + billing (Cloudflare Workers/D1/DO/R2) |
| [`parachute.computer`](./parachute.computer) | Public site + blog; teaches the ladder |
| [`parachute-brain`](./parachute-brain) | Internal team surface over the project vault (merge delegated) |
| [`parachute-scribe`](./parachute-scribe) | Folding into Vault (ratified 2026-07-03); archives at fold Phase 3 |
| [`parachute-patterns`](./parachute-patterns) | **ARCHIVING** (`Decisions/2026-07-03-patterns-archive`) — audit-driven rescue PR, then GitHub-archive |
| everything else | exploration (`parachute-pebble` = L1 capture client, active side project) or graveyard — see `Canon/Modules` |

**Compatibility labels** (the old "committed-core" axis): vault + surface-client/surface-render have real users — keep compatible; hub + cloud are the shipped doors — standard care, migrations for operator-visible changes; agent, surface-host near-zero — breaking OK; scribe frozen (folding into vault).

## The dev ritual (with vault access)

**Orient → Claim → Log → Release.** Before substantive work, claim a `work` note (assignee, `repo/<slug>` tag per repo touched, `status: in-progress`); log progress and surprises as you go; decisions made in-session get a `Decisions/<date>-<slug>` note in the same session (**sessions are the new meetings**); release with `status: in-review|shipped|dropped`. Read-only investigations under ~3 commands skip the Claim. **The vault is the brain — no loose design/strategy files at the workspace root** (historical ones live in `docs/historical/`). Detail + the GitHub-issues boundary: [docs/process/development.md](./docs/process/development.md).

## Working across repos — the TL;DR

The main thread **orchestrates**; blocking subagents execute. `cd` into the target repo before dispatch (or brief the agent to cd first — otherwise it reads this file instead of the repo's CLAUDE.md). One PR at a time per repo; single dev branch `ag-unforced-dev`; branch first, then edit. **Verify subagent claims against ground truth** (`git show`, `gh pr diff`) before acting — especially negative findings and anything that reverses committed work. **Every PR gets an independent reviewer (foreground) before merge**; specialists in [.claude/skills/review-subagents/](./.claude/skills/review-subagents/SKILL.md) run when the diff touches their domain. Full discipline: [docs/process/orchestration.md](./docs/process/orchestration.md).

## Governance (one breath)

No auto-merge — Aaron merges (brain excepted) · every code-touching PR bumps `rc.N`, tag pushed on merge, CI publishes · a contracts check rides every review · architectural shifts ship a migration file. Full rules: [docs/process/governance.md](./docs/process/governance.md).

## Local dev

Modules run **bun-linked** from checkouts — `parachute start <svc>` follows the checked-out branch (short service names: `restart surface`, not `restart parachute-surface`). After merging a frontend bump: `bun run build` in the repo, then `parachute restart <svc>`. Post-merge sync: `git fetch && git pull --ff-only` in affected repos (skip repos with uncommitted work); pull `main` before starting any new work.

@docs/index.md
