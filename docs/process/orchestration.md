# Working across repos — the dispatch discipline

The main thread is the **orchestrator**, not the executor. Substantial code-shipping work goes to blocking subagents; the orchestrator coordinates streams, verifies outputs, and keeps its context clean of execution detail.

## Dispatch model

Default to blocking subagents (`Agent({ subagent_type: "general-purpose" })`). Spawn, do focused work, return result, terminate. For cross-repo work, dispatch one subagent per repo concurrently in a single tool call. Use `run_in_background: true` for genuinely long-running work with unrelated work in the meantime.

**Do it yourself instead when:** one-line edits with full context loaded; read-only investigations under ~3 commands; memory/vault writes; final review of commits before merge.

**Deep thinking** (design, architecture deliberation, research synthesis, gnarly trade-offs) goes to a **Fable** agent (`model: "fable"`) — plans and analysis, not code; the plan comes back to the orchestrator/builders to execute.

## Per-repo discipline

1. **Concurrent PRs per repo are fine when they're disjoint** (changed 2026-07-26 — the old rule was one-at-a-time, and it cost real throughput the first night work arrived faster than it merged: four finished branches sat behind the least important of the four).
   **The test, and it's the only definition:** *if you can't state the merge as "take one side plus these edits," it isn't disjoint.* A shared file is a **trigger to apply the test**, not an automatic serialize — two branches making independent edits to one file are fine; two branches restructuring it are not.
   The counterexample that motivated the exception: a views on-ramp and a tag-page extraction both rewrote `ViewSurface.tsx`, and reconciling them wasn't conflict resolution — it was a component-API decision (who owns the page wrapper when the width class derives from draft state only the inner component holds). That belongs to the author, not to whoever rebases second.
   **Versions don't collide anymore — that concern is moot.** Feature PRs never touch the `package.json` version line or `CHANGELOG.md` at all (governance.md rule 2); the bump happens once per batch, as the final commit of the `next → main` release PR Uni cuts, not in any feature branch. (This section used to explain how to live with the version/changelog line colliding on every PR — fixed 2026-07-29 by moving the bump off feature PRs entirely, then folded into the merge train 2026-08-14, so there's no "assign the version when you open" step left to describe.)
   Side-discoveries still → `gh issue create`.
   **Reviews parallelize even when merges don't.** A branch can be reviewed before it's a PR; it then opens pre-cleared. But "pre-cleared" describes the *commit* reviewed, not the branch — **fold findings and the same reviewer re-checks the delta** before merge. Timing changes; the gate doesn't.
2. **Single dev branch `ag-unforced-dev`** — two branches per repo (`main` + dev). Builders work the dev branch, PR to `next`, reset to track main after merge. **Verify the merge succeeded (`state == MERGED`) before resetting** — a transient merge failure plus unconditional hygiene force-push has clobbered an open PR before.
3. **Branch first, then edit.** Editing on `main` then checkout+reset wipes your own work; `git status` before any reset.
4. **`cd` into the target repo before dispatch** — or brief the agent to `cd` as its first action. Otherwise it reads the workspace CLAUDE.md instead of the repo's and may claim the wrong task.
5. **One agent at a time per repo.** Don't run destructive git ops in a repo where a background agent is working; a concurrent session may also be in the repo — re-fetch the base and never clobber a dev branch carrying commits you don't recognize.
6. **In a bun-linked repo, the shared checkout IS what gets served on the next restart — not a build.** `parachute start/restart <svc>` (and, for the hub daemon itself, its launchd unit) runs straight from the checked-out code, so an in-progress branch left checked out means the next restart — Aaron's, a crash-respawn's, another session's, not just yours — silently serves unreviewed code. The failure is invisible: a feature branch containing the awaited work succeeds exactly as expected. So: **do branch work in these repos from a `git worktree`, never the shared checkout**, and **restore the checkout to `main`, clean, the moment you're done** — every time, not just when you remember. (Keep worktree paths short — long ones break workerd's `mkdirat`; and if the repo has a sibling `file:` dependency, e.g. cloud's `../parachute-vault/core`, that sibling needs to be reachable at the same relative position from the worktree.) Before running `parachute restart <svc>` yourself, confirm the checkout is on `main` and clean first — a working branch is not evidence you restarted the right code.

## Briefing

Provide discoverable context (branch head sha, open PR number, landmarks). Spell out verifiable success criteria ("bump to rc.N+1, push, open PR with this body, exit"). Don't assume the subagent shares your in-memory model of repo state. Tell it its final message is a report, not a user-facing message. Subagents can't receive background-task notifications — brief them to poll directly, and if one stalls "waiting", resume it with that reminder.

## Verify subagent outputs before acting

Treat claims as inputs to verify, not facts — especially **negative findings** ("I don't see X") and **reversal-of-committed-work** actions. Run `git show <sha>:<path>` or `gh pr diff <num>` to confirm; agents may be reading a stale tree. Negative scans need positive controls (prove the scanner saw content before believing "nothing found"). Verification is one command; acting on a false claim costs a reverted commit.

## The reviewer gate

**Every PR gets an independent reviewer before merge — even doc-only ones.** The reviewer is a `general-purpose` subagent with an inline reviewer brief — there is no dedicated reviewer agent type. Briefing, cadence (foreground, delta verdicts, concurrent-when-disjoint, fold-gets-re-checked), and the specialist roster live in [.claude/skills/review-subagents/SKILL.md](../../.claude/skills/review-subagents/SKILL.md).

## Session boundary

Subagents don't survive `/resume`. Before a session boundary, capture in-flight state (branch, open PR, next step) somewhere the fresh session will look — the work note or the PR body.
