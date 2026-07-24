---
name: review-subagents
description: >-
  Dispatch the workspace's review agents over a delivered PR before the merge decision. The
  generalist reviewer is MANDATORY for every PR; the domain specialists here run additionally
  when the diff touches their domain (wire shapes / OAuth / scopes / production gates). TRIGGER
  when: a builder has delivered a PR and it needs review before merge, or a batch of PRs needs
  a once-over-the-whole-batch specialist pass.
---

# review-subagents — the workspace review roster

The **generalist reviewer** runs on **every PR, no exceptions** — even doc-only ones. There is
no dedicated reviewer agent type: dispatch a **`general-purpose` subagent with an inline
reviewer brief** — independent of the builder, briefed with the PR number, what to verify, the
verdict format (**SHIP / NO-SHIP + must-fixes**), read-only discipline (`gh pr diff` + ref-reads
as ground truth, no edits), and gates run sandboxed (never against the live install). The
**specialists** below each defend ONE narrow invariant and run *in addition* when the diff
touches their domain. This is Lucian's
recipe adapted to Parachute: one citable invariant per agent, a falsifiable litmus, findings
cite the canonical contract — never taste. (See regenos' `creating-review-subagents.md` for the
authoring recipe; adopt the shape, not the letter.)

## Cadence

- Generalist: once per PR. The orchestrator dispatches it — builders can't dispatch reviewers
  recursively.
- Specialists: once per PR **when the diff touches their domain** (see each brief's trigger
  list). For a batch/sweep, run each relevant specialist ONCE over the collective diff, never
  per item.
- Blockers/must-fixes go back to the builder to fold inline (same PR, same rc); the same
  reviewer re-checks the fold. Nits fold inline too when diff-relevant; else `gh issue create`.
- All reviews run **foreground/blocking** — background reviewers starve behind long builders.
- A post-review **delta on a security surface** (auth, deploy, credentials) gets a delta verdict
  from the same or a fresh reviewer before merge — no self-verified folds there.
- **Serial per repo** — one PR through review and merge before the next PR in that repo.

## How to run a specialist

Spawn a `general-purpose` subagent whose prompt = the specialist's brief file below
+ the PR reference (`gh pr diff <n>` as ground truth) + this line up front: **"This is a
pattern-congruence review, NOT a general code/security review — report only violations of the
brief's one invariant, as: location, issue, one-line fix."** (The security-brief style is
load-bearing: extended exploit narratives kill sessions.)

## Roster

| Brief | Invariant it defends | Runs when the diff touches… |
|---|---|---|
| [wire-contract-congruence.md](wire-contract-congruence.md) | One wire contract across the two doors | REST/MCP shapes, OAuth issuer behavior, portable-md, module protocol, anything hub↔cloud |
| [auth-and-scope.md](auth-and-scope.md) | Tokens minted/accepted only per the issuer contract; scopes never silently widen; prod gates never weaken | auth, tokens, scopes, JWKS, billing gates, `__test/*` routes, ENVIRONMENT checks |
| [release-check.sh](release-check.sh) | Structural release hygiene (version bump, lockfile sync) — a SCRIPT, not an agent | every code PR: run it, don't spawn an LLM for a checklist |

## Adding a specialist

One invariant per agent (two checks may share an agent only if they share a frame). Write the
litmus as the failure the pattern prevents, not the rule restated. Cite the canonical doc — if
there's no canonical doc, write one first (an agent enforcing an unwritten rule just relitigates
it). Prefer a compile-time/test guard where the property is structural; a reviewer earns its
keep only for judgment cases. Add the brief here + to the roster table.
