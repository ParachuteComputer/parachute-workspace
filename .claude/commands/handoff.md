---
description: Generate a handoff doc capturing this session's state so a fresh session can pick up cleanly. Sidesteps the broken in-process-teammate resume.
---

Generate a handoff document at `/Users/parachute/ParachuteComputer/scratch/HANDOFF-$(date +%Y-%m-%d-%H%M).md` capturing the current session state.

The goal: the user will close this Claude Code session and start a fresh one. Session resume doesn't restore in-process tentacles (known Claude Code limitation per https://code.claude.com/docs/en/agent-teams.md), so we use a handoff doc as the bridge. The new session reads this doc as its first orientation, replacing the broken `/resume` flow.

## What to capture

Survey the session state across these dimensions, then write a single coherent handoff doc.

### A. TL;DR (3 sentences max)

What did this session aim to do, what got done, what's the next handle to grab.

### B. In-flight work (active PRs / issues / dispatches)

For each PR or issue currently in motion, write a block:

- **Repo + number + title**
- **State**: open / merged / draft / closed; for open PRs include the reviewer verdict (LGTM / changes-requested / pending)
- **HEAD sha + branch**
- **Gates**: cite literal pass/fail numbers if known
- **Next action**: who does what
- **Context**: 1-3 sentences on why this matters / what was hard / what was decided

Get current data via:
- `gh pr list --repo ParachuteComputer/<repo>` for each repo with active work
- `git log --oneline origin/main..origin/ag-unforced-dev` for in-flight branches

### C. Pending Aaron's hand (off-Claude work)

Things only Aaron can do:
- npm publishes (his 2FA shell)
- Merge clicks on repos in his merge category (hub, site, scribe, notes)
- Decisions still waiting
- Reviews of long-form drafts (beta emails, blog posts)

### D. Decisions made this session

List the architectural / process calls that were made, with one-line why + pointer to where captured:
- "Option A locked in (single container, hub-as-supervisor for v0.6) — memory entry `project_v06_...`"
- "Reviewer outputs need spot-checking — new memory entry `feedback_verify_agent_outputs`"
- etc.

### E. Open questions / pending decisions

Anything that's been raised but not resolved. Include the relevant context + your current lean if any.

### F. Local working-tree state per repo

For each repo with WIP:
- branch, HEAD sha, dirty/clean, uncommitted files (if any)

Run `cd <repo> && git status -sb && git log --oneline -1` per committed-core repo. Skim quickly — most will be clean.

### G. Tentacle / subagent state worth preserving

Brief notes on what each tentacle was doing — they'll die at session end. Capture only what won't be obvious from git state. Usually:
- "hub: just finished PR #262, standing by"
- "vault: idle, last work merged"
- etc.

### H. Pointers (where to find things)

- Relevant scratch docs (recent THINKING / REFLECTION / AUDIT files)
- Newly-filed issues worth tracking
- Recent memory entries written this session
- Design docs touched

### I. Next-session orientation checklist

A clear "first things to do" list for the fresh session:

1. Read `~/ParachuteComputer/CLAUDE.md` (workspace conventions)
2. Read `~/.claude/projects/-Users-parachute-ParachuteComputer/memory/MEMORY.md` (the index)
3. Read this handoff doc fully
4. Check `Current/Parachute` MCP for live ecosystem state
5. Don't preemptively spawn tentacles — dispatch only when work needs them
6. If a tentacle's session-prior work is referenced, the tentacle is gone — re-dispatch as needed

## Style

- Skimmable, not encyclopedic. The new session should be oriented in ~3 minutes of reading.
- Concrete: file paths, issue numbers, SHAs, version strings. Not vague references.
- Honest about uncertainty. If something isn't decided, say so + don't fake confidence.
- Don't recap conversation. Capture state + decisions.

## After writing the doc

1. Output the absolute file path so Aaron can find it.
2. Briefly summarize the top-3 things in the doc so Aaron knows what's there without opening it.
3. End the session by suggesting Aaron close this session and start a fresh one with this doc.
