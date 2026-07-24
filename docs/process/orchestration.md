# Working across repos — the dispatch discipline

The main thread is the **orchestrator**, not the executor. Substantial code-shipping work goes to blocking subagents; the orchestrator coordinates streams, verifies outputs, and keeps its context clean of execution detail.

## Dispatch model

Default to blocking subagents (`Agent({ subagent_type: "general-purpose" })`). Spawn, do focused work, return result, terminate. For cross-repo work, dispatch one subagent per repo concurrently in a single tool call. Use `run_in_background: true` for genuinely long-running work with unrelated work in the meantime.

**Do it yourself instead when:** one-line edits with full context loaded; read-only investigations under ~3 commands; memory/vault writes; final review of commits before merge.

**Deep thinking** (design, architecture deliberation, research synthesis, gnarly trade-offs) goes to a **Fable** agent (`model: "fable"`) — plans and analysis, not code; the plan comes back to the orchestrator/builders to execute.

## Per-repo discipline

1. **One PR at a time per repo.** Finish through merge before the next. Side-discoveries → `gh issue create`.
2. **Single dev branch `ag-unforced-dev`** — two branches per repo (`main` + dev). Builders work the dev branch, PR to main, reset to track main after merge. **Verify the merge succeeded (`state == MERGED`) before resetting** — a transient merge failure plus unconditional hygiene force-push has clobbered an open PR before.
3. **Branch first, then edit.** Editing on `main` then checkout+reset wipes your own work; `git status` before any reset.
4. **`cd` into the target repo before dispatch** — or brief the agent to `cd` as its first action. Otherwise it reads the workspace CLAUDE.md instead of the repo's and may claim the wrong task.
5. **One agent at a time per repo.** Don't run destructive git ops in a repo where a background agent is working; a concurrent session may also be in the repo — re-fetch the base and never clobber a dev branch carrying commits you don't recognize.

## Briefing

Provide discoverable context (branch head sha, open PR number, landmarks). Spell out verifiable success criteria ("bump to rc.N+1, push, open PR with this body, exit"). Don't assume the subagent shares your in-memory model of repo state. Tell it its final message is a report, not a user-facing message. Subagents can't receive background-task notifications — brief them to poll directly, and if one stalls "waiting", resume it with that reminder.

## Verify subagent outputs before acting

Treat claims as inputs to verify, not facts — especially **negative findings** ("I don't see X") and **reversal-of-committed-work** actions. Run `git show <sha>:<path>` or `gh pr diff <num>` to confirm; agents may be reading a stale tree. Negative scans need positive controls (prove the scanner saw content before believing "nothing found"). Verification is one command; acting on a false claim costs a reverted commit.

## The reviewer gate

**Every PR gets an independent reviewer before merge — even doc-only ones.** The reviewer is a `general-purpose` subagent with an inline reviewer brief — there is no dedicated reviewer agent type. Briefing, cadence (foreground, delta verdicts, serial per repo), and the specialist roster live in [.claude/skills/review-subagents/SKILL.md](../../.claude/skills/review-subagents/SKILL.md).

## Session boundary

Subagents don't survive `/resume`. Before a session boundary, capture in-flight state (branch, open PR, next step) somewhere the fresh session will look — the work note or the PR body.
