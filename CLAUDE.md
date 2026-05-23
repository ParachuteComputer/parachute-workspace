# Parachute Computer

The top-level workspace for the Parachute ecosystem. Each Parachute module is its own git repo under this directory; this CLAUDE.md captures workspace-wide practices.

**On entering this directory, read `Current/Parachute` from the parachute-vault MCP.** It's the live state of the ecosystem — what's shipped, what's in flight, what's parked, who's using it.

## Committed core vs explorations

The four committed-core modules are the product surface. Two more repos (patterns, site) exist to support them but aren't themselves modules.

| Repo | Role | Status |
|---|---|---|
| [`parachute-vault`](./parachute-vault) | Vault — knowledge graph + MCP | committed core |
| [`parachute-app`](./parachute-app) | App — UI host module (Notes ships as first canonical app via auto-bootstrap; Gitcoin Brain / Unforced Brain / etc. mount as further apps) | committed core |
| [`parachute-scribe`](./parachute-scribe) | Scribe — transcription worker | committed core |
| [`parachute-hub`](./parachute-hub) | Hub — the portal on :1939, OAuth issuer, CLI surface (renamed from `parachute-cli` 2026-04-26) | committed core |
| [`parachute-patterns`](./parachute-patterns) | Cross-cutting conventions (docs-only) | core support |
| [`parachute.computer`](./parachute.computer) | Public site + blog | core support |
| [`parachute-runner`](./parachute-runner) | Runner — vault-as-job-substrate, spawns claude -p against tag:job notes | shipped (Phase 1 complete 2026-05-21); not yet promoted to committed-core |
| [`parachute-notes`](./parachute-notes) | Notes — UI bundle (`@openparachute/notes-ui`) consumed by parachute-app; standalone daemon deprecated 2026-05-22 ([DEPRECATED.md](./parachute-notes/packages/notes-daemon/DEPRECATED.md)) | deprecating (Phase 2 of migration arc; Phase 3 retires daemon, Phase 4 archives repo) |
| [`parachute-channel`](./parachute-channel) | Channel — webhook fan-out | exploration — may retire |
| [`parachute-agent`](./parachute-agent) | Agent — Claude-in-containers (retired 2026-05-20; see [DEPRECATED.md](./parachute-agent/DEPRECATED.md)) | retired |

Anything else in the workspace (`parachute-narrate`, `parachute-daily`, `prism`, `tailshare`, `parachute-octopus`, etc.) is exploration, archive, or unrelated. The committed-core line was redrawn 2026-05-22 (vault/app/scribe/hub) when Notes-as-daemon migrated to Notes-as-app inside parachute-app — features, marketing, and pattern docs name the four committed-core modules; everything else lives but isn't promoted.

**Note on `parachute-notes` migration (2026-05-21 → ongoing)**: the notes-daemon shipped as committed-core through launch (2026-04-23), but Notes-as-UI was always conceptually an "app that consumes a vault," not a backend service. Once parachute-app shipped (2026-05-21) with auto-bootstrap of `@openparachute/notes-ui`, notes-daemon's role collapsed to "static-serve wrapper." The 4-phase deprecation arc lives in [the parachute-app design doc §16](./parachute.computer/design/2026-05-21-parachute-apps-design.md). Operators on legacy notes-daemon installs continue to work; hub redirects `/notes/*` → `/app/notes/*` for backwards compat. Port 1942 reclaims at Phase 3.

**Note on `parachute-agent`**: promoted to committed-core 2026-05-05, retired 2026-05-20. The Gitcoin Brain pattern (vault-as-job-substrate, ~200-line Python cron runner spawning `claude -p` with inline MCP config) proved the "Claude in containers" architecture was overengineered for the owner-operated, trusted-vault use case it was built for. The trust-gradient insight (see [`parachute-patterns/patterns/trust-gradient-isolation.md`](./parachute-patterns/patterns/trust-gradient-isolation.md)) informed the decision. [`parachute-runner`](./parachute-runner) is the lightweight successor primitive for owner-operated automation (Phase 1 complete 2026-05-21); `parachute-cloud` (TBD) will handle multi-tenant container isolation when that demand materializes.

**Note on hub's `FIRST_PARTY_FALLBACKS`**: that registry was a *transitional vendored-manifest fallback* (one entry per module that hadn't yet shipped its own `.parachute/module.json`). As of 2026-05-21, vault/scribe/runner self-register via the canonical pattern (see [`parachute-patterns/patterns/module-self-registration.md`](./parachute-patterns/patterns/module-self-registration.md)) and their FALLBACK entries retired. Hub retains `KNOWN_MODULES` (a minimal install-bootstrap registry) for the install-time path. Committed-core status is a commitment statement; hub's manifest registries are implementation details — they're separate axes.

## Working across repos

The main thread is the **orchestrator**, not the executor. Substantial code-shipping work goes to blocking subagents; the orchestrator coordinates streams, verifies outputs, and keeps its context clean of execution detail.

**Dispatch model.** Default to blocking subagents (`Agent({ subagent_type: "general-purpose" })` or a specialized agent — see the available list in CLAUDE Code's docs). Spawn, do focused work, return result, terminate. For cross-repo work, dispatch one subagent per repo concurrently in a single tool call so they run in parallel. Use `run_in_background: true` sparingly — only when work is genuinely long-running and there's unrelated work in the meantime. The persistent team/tentacle apparatus (`subagent_type: "tentacle"` + `TeamCreate` + `SendMessage`) exists but has been fragile here (slot-squatting after restart, `isActive: null` is not a death signal, `/resume` kills them, working-tree collisions when a one-shot races a persistent agent). Reach for it only when there's genuinely multi-round iteration too expensive to re-brief.

**When to do it yourself instead.** One-line edits with full context already loaded; read-only investigations under ~3 commands; memory writes; final review of someone else's commits before merge. The dispatch overhead beats the value for trivial work.

**Per-repo discipline.**
1. **One PR at a time per repo.** Finish through merge before starting the next. Side-discoveries → `gh issue create`, not parallel branches.
2. **Single branch `ag-unforced-dev`.** Two branches per repo only — `main` + `ag-unforced-dev`. Subagents work on the dev branch, PR to main, reset to track main after merge. No per-feature branches.
3. **`cd` into the target repo before dispatch.** Subagents inherit cwd from the parent's initial shell, NOT the current Bash cwd after a `cd` command. Without a `cd` first, the subagent reads the workspace `CLAUDE.md` instead of the repo `CLAUDE.md` and may silently claim an unrelated workspace task.

**Briefing.** Provide discoverable context (branch head sha, open PR number, landmarks). Spell out verifiable success criteria ("bump to rc.N+1, commit, push, open PR with this body, exit"). Don't assume the subagent shares the orchestrator's in-memory model of repo state.

**Verify subagent outputs before acting.** Treat claims as inputs to verify, not facts. Especially **negative findings** ("I don't see X") and **reversal-of-committed-work** actions (cancelling a fold, reverting a commit, force-pushing). Run `git show <sha>:<path>` or `gh pr diff <num>` to confirm — agents may be reading a stale working tree. Cost asymmetry: verification is one command; acting on a false negative costs a reverted commit and lost trust.

**Reviewer dispatch is mandatory.** Every PR gets a reviewer subagent before merge — even doc-only ones.

**Session boundary.** Subagents don't survive `/resume`. Bridge sessions with `/handoff` — capture in-flight state in a doc the fresh session can read.

## When making architectural shifts

When a PR decides an architectural shift — committed-core changes, canonical install path changes, a doc statement that's quoted across the workspace changes — ship a `parachute-patterns/migrations/YYYY-MM-DD-<slug>.md` file in the same PR.

The file is a propagation checklist. It lists every code/doc location that needs updating + tracks which PRs landed each item. Future contributors see "is this shift fully propagated?" at a glance.

See [`parachute-patterns/migrations/README.md`](./parachute-patterns/migrations/README.md) for the discipline + format. The [2026-05-21 Notes-as-app migration](./parachute-patterns/migrations/2026-05-21-notes-as-app.md) is the canonical example (retroactive — written after the shift to seed the discipline).

Run [`parachute-patterns/scripts/audit-canonical-refs.sh`](./parachute-patterns/scripts/audit-canonical-refs.sh) after shifts (or before releases) to catch missed propagations.

Why the discipline exists: the Notes-as-app shift caught us out — hub's setup wizard hardcoded "install Notes" as the canonical first install even after the architecture had moved to "install App which auto-bootstraps notes-ui." An audit then found ~9 more stale references. A migration file in the originating PR would have made the propagation work obvious.

## Governance (settled 2026-04-25)

Three rules, captured in [`parachute-patterns/patterns/governance.md`](./parachute-patterns/patterns/governance.md):

1. **No auto-merge.** Tentacles open PRs and report; team-lead reviews and writes a verification summary; the human (Aaron) clicks merge — except in repos where team-lead has delegated merge authority (currently `agent`, `vault`, `patterns`). All seven core + core-support repos (vault, notes, scribe, agent, hub, patterns, parachute.computer) have branch protection on `main` enforcing PR-required + no-force-push + no-deletion. Required-review-count is `0` while solo-team; bumps to ≥1 when a second human contributor joins.
2. **RC versioning before `@latest`.** Pre-1.0, every code-touching PR bumps the `rc.N` suffix only — keep `0.X.Y` fixed across the chain (`0.5.8-rc.1` → `rc.2` → `rc.3` …). When Aaron explicitly says ready-for-release: drop the `-rc` suffix, ship the same `0.X.Y` stable (same patch number as the rc chain), `npm publish --tag latest`. Doc-only PRs skip rc per the doc-only exemption. Don't fragment a release into many patch bumps mid-validation. The starting `Y` is the next-patch from the prior stable — e.g. after `0.5.7` ships, the next code-touching rc chain runs at `0.5.8-rc.N` → `0.5.8` stable. (Canonical: `parachute-patterns/patterns/governance.md` rule 2.)
3. **Patterns check in every review.** Each PR review surfaces which patterns the change touches, whether it conforms, whether it establishes / changes a pattern.

## Cross-cutting conventions

[`parachute-patterns/`](./parachute-patterns) is the single source of truth for ecosystem-wide conventions: naming, brand, schemas, OAuth scopes, module protocol, ports, governance. Before shipping code that crosses a pattern boundary, check the relevant file there. If the convention is wrong, update the pattern in that repo first, then adopt downstream.

## Local development setup

All committed-core modules run via `bun link` from the local checkout — that way `parachute start <svc>` follows whatever branch is checked out, not a published npm version. Current links:

- `@openparachute/vault` → `parachute-vault`
- `@openparachute/notes` → `parachute-notes`
- `@openparachute/scribe` → `parachute-scribe`
- `@openparachute/agent` → `parachute-agent`
- `@openparachute/hub` → `parachute-hub`

After merging a PR that bumps a frontend module (e.g. notes), the running daemon serves the new code on restart only if the build artifact is fresh — `bun run build` in the repo before `parachute restart <svc>`. Hub's `~/.parachute/services.json` caches the version string per service; `parachute upgrade <svc>` refreshes most fields but doesn't always refresh the cached version on the bun-linked path (hub#243 tracks). If `parachute status` shows a stale version while the bundle is current, manually update `services.json` or wait for that hub fix.

## Post-merge sync

Practice (simple version, settled 2026-04-25):

1. Aaron tells the team-lead when he merges PRs.
2. Team-lead syncs the affected repos with `git fetch && git pull --ff-only`. Skip repos with uncommitted work on a feature branch — don't clobber WIP.
3. Pull `main` as the first step before starting any new work — every subagent, every dispatch.

The full pattern is in [`parachute-patterns/patterns/post-merge-hygiene.md`](./parachute-patterns/patterns/post-merge-hygiene.md).

## Key design docs

Current-era architecture docs in [`parachute.computer/design/`](./parachute.computer/design):

- `2026-04-20-module-architecture.md` — module protocol (info / config / services.json / well-known)
- `2026-04-20-hub-as-portal-oauth-and-service-catalog.md` — OAuth architecture (hub as issuer)
- `2026-04-20-cloud-offering-sketch.md` — cloud deployment shape

## Launch artifacts (historical)

Launch was 2026-04-23. The following files in this workspace root are historical reference:

- `RELEASE-NOTES-launch-day.md` — per-package GitHub Release body drafts
- `BETA-EMAIL-launch-day.md` — beta user email draft
- `WAKE-UP-SUMMARY.md` — mid-session state snapshot from launch week

The blog post is live at [`parachute.computer/blog/parachute-is-here/`](./parachute.computer/blog/2026-04-23-parachute-is-here.md). Smoke scripts are in their per-repo locations: `parachute-hub/LAUNCH_SMOKE.md`, `parachute-notes/MOBILE_SMOKE.md`.

---
