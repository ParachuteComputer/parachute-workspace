# Process audit — 2026-05-17

Reference document for the patterns + open-issues + memory audit. Source for downstream patterns-cleanup PR + v0.5 sequencing decisions.

## 1. parachute-patterns repo state

**46 markdown files across 9 directories.** No orphans, no duplication. All recently active (May 2026). Not bloated.

### Per-directory tally

| Directory | Files | Status |
|---|---|---|
| `patterns/` | 33 | Heavy auth cluster (8) + module cluster (5); consolidation opportunity |
| `research/` | 7 | Substantive; auth + cloudflare + surface direction |
| `guides/` | 2 | Fresh, user-facing (building-a-surface, multi-writer-workspace) |
| `adoption/` | 2 | migration-notes actively updated; checklist stable-by-design |
| `cookbook/` | 2 | Minimal but active (vault-portable-export + README) |
| `brand/` | 3 | Locked-by-design, no expected churn |
| `schemas/` | 3 | Core contracts, locked |
| `modularity/` | 2 | Foundational philosophy, locked |
| `naming/` | 3 | Recently refreshed (repos, bins, packages) |

### governance.md analysis

Four rules, 1091 words, updated 2026-05-15. Coherent structure; no bloat.

1. **No auto-merge** — human review + merge gate.
2. **RC versioning before @latest** — publish `@rc` first, deliberate promotion to `@latest`.
3. **Patterns check in every review** — surface which patterns are touched + conformance.
4. **PR cadence: bundle by session, not by issue** — one PR per coherent work session; multiple commits inside.

Cross-references intact; no stale links. Rule 4 added 2026-05-13 in response to Aaron's push-back on issue-per-PR drift; reflected in memory `feedback_bundle_default_pr_cadence`.

### Consolidation opportunities (not urgency)

**Auth cluster (8 files):** `oauth-dcr-approval` + `oauth-scopes` + `tag-scoped-tokens` + `hub-as-issuer` + `service-to-service-auth` + `token-auth` + `well-known-discovery-rfc` + (the future scope-guard pattern). These are complementary, not duplicate, but a narrative umbrella doc ("Auth stack: OAuth 2.0 and token scoping") cross-referencing each piece would aid onboarding.

**Module discovery cluster (5 files):** `module-protocol` + `module-json-extensibility` + `module-ui-declaration` + `vault-mcp-discovery` + `mcp-transport`. Distinct concerns; umbrella doc ("Module discovery + installation") would help nav.

## 2. Open issues across repos

**74 total open.** ~18 v0.5-critical. ~13 stale (>14 days, low priority).

| Repo | Open | v0.5 critical | Stale (>14d) | Health |
|---|---|---|---|---|
| vault | 37 | 5 | 2 | Heavy load, all recent activity, scale/format clustering |
| hub | 9 | 3 | 2 | Focused on onboarding + auth migration |
| notes | 8 | 4 | 0 | Capture flow + format support |
| scribe | 4 | 2 | 2 | Design-gated (MCP shape) |
| agent | 0 | — | — | ✓ Clean |
| patterns | 10 | 2 | 6 | Cross-cutting fixes orphaned |
| site | 6 | 2 | 1 | v0.5 aligned |

### Substantial issues (v0.5 wave)

**Vault (5):**
- `#338` — Performance at scale (10k+ notes) — big yes
- `#328` — File-extension support (non-markdown notes) — already shipping
- `#326` — WAL mode for multi-process access
- `#315` — Refresh docs/HTTP_API.md
- `#300` — Audit log table

**Hub (3):**
- `#253` — Setup walkthrough fresh-machine smoke + polish
- `#252` — Multi-user UX (sign-in, user-mgmt, consent)
- `#212` — Hub-as-sole-AS migration (umbrella, multi-phase)

**Notes (4):**
- `#138` — Phase 2 format-aware rendering (CSV/YAML/JSON/MDX)
- `#136` — Header brittle under text-size scaling
- `#128` — notes-app config as vault note
- `#126` — Capture: generate path locally + pre-fill

**Site (2):**
- `#40` — OAuth silent-approve human-prose explainer
- `#39` — Install page accuracy + fresh-eyes test

### Stale candidates worth batch-triaging post-v0.5

- vault `#72` (34d), `#20` (41d) — exploratory + roadmap items
- patterns `#38, #37, #35, #34, #27, #25` (12-14d) — cross-cutting pattern fixes + research synthesis, orphaned
- hub `#172, #178` (11-13d) — architectural refactor + cloudflare infra
- scribe `#35, #34` (14d) — paired, awaiting design

### Risk flags

1. **Auth modernization fragmentation** — patterns#38/#37, vault#282 (phase 6: pvt_* deprecation), hub#212 (sole-AS migration), patterns research/auth-architecture-shape are all converging on multi-phase refactor with no single coordinating issue. **Recommend: meta-issue "Auth stack: v0.x–v1.0 roadmap"** sequencing the phases + cross-repo dependencies.

2. **Format support coordination** — vault#328, vault#306, notes#138 are aligned but lack an explicit pattern doc. **Recommend: file `parachute-patterns#NEW` "Pattern: format-aware notes and surfaces"** codifying the extension + sidecar metadata + format-aware-renderer triad.

3. **Pattern research orphanage** — 6 patterns issues stale 12-14 days. Need batch-triage decision after v0.5: close-as-deferred OR restart-with-implementation.

## 3. Memory file state

44 entries across 6 categories. No duplication, no obvious staleness. Tight, living system.

- Tentacle + team-lead workflow (8)
- PR flow + merge authority (11)
- Operator-state migrations (1)
- Testing + quality (7)
- Architecture + ecosystem (4)
- Communication (2)

Most recent updates (2026-05-13) sync with governance Rule 4. Oldest entries (2026-04-15) are foundational and stable-by-design. Cross-references to concrete GitHub issues throughout — grounded in evidence, not aspiration.

**Post-v0.5 action**: review 2026-04-15-era entries to consolidate any obsolete findings. Not urgent.

## 4. Overall health

- Patterns repo: ✓ Healthy. Non-bloated.
- Issue inventory: ✓ Organized. Heavy v0.5 alignment.
- Process + memory: ✓ Tight, co-evolving.

No blocker-level issues detected. Parachute is in healthy post-launch iteration mode.

---

_Audit compiled 2026-05-17 via research-agent pass over patterns repo + open-issue lists across 7 repos + memory file._
