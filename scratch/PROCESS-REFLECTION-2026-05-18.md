# Process reflection — 2026-05-18

Captured at Aaron's request before closing this Claude Code session to start fresh. Goal: identify what's confusing in current setup (system prompts, memory, tentacle model) and what to change for a cleaner development practice going forward.

Authored by team-lead while watching hub#260 / PR #262 land. Real observations from this session and the prior overnight.

## TL;DR

The persistent-tentacle teammate model is doing more work than the underlying machinery supports. Slot accumulation, silent stalls, phantom dual-actor narratives, and unreliable liveness signals collectively burn ~30% of session bandwidth on coordination overhead. The dispatch model could be much simpler.

Memory has accumulated to 44 entries with overlap and minor contradictions. Tightening to ~25 consolidated entries would help a new session orient faster.

Agent outputs (tentacle progress messages, reviewer findings) need verification before action — this session had concrete failures from acting on un-verified citations. Trust-but-verify needs to extend beyond just tentacle code to reviewer + research outputs.

## What's broken — observed this session and overnight 2026-05-17/18

### 1. Slot-squat / phantom dual-actor narratives

**Symptom**: every tentacle dispatch produced 2–3 near-identical messages from different "slots." Each slot narrates from its own working-tree snapshot, so when one slot commits, another slot sees the commit and concludes "a parallel actor wrote that."

**Consequences this session**:
- Hub tentacle holding writes mid-C4 thinking it would conflict with a non-existent peer
- Asking "what's the call?" when nothing needed deciding
- Misattributing its own commits to phantom collaborators (often "Aaron")
- Burning context with 1500-word triplicated messages

**Root cause**: `~/.claude/teams/parachute-build/config.json` accumulates dead slots that still route messages. CLAUDE.md addresses this reactively (`Post-restart hygiene`) but it's never preventive.

### 2. Tentacle silent-stall

**Symptom**: tentacle sends "here's my plan, here are my questions" and holds for confirmation even when defaults are clearly stated and the relevant memory entry (`feedback_dont_block_on_silent_input`) says to act on defaults within 15 min.

**Consequences this session**:
- After C1, tentacle held 6h waiting for sequencing approval that wasn't needed
- After C2, tentacle held briefly thinking a parallel actor was mid-write
- Aaron had to ping twice ("seems stopped" / "confirm its still active?") to confirm work was happening

**Root cause**: deferential-by-default outweighs the corrective rule. The "send a plan, wait for ack" pattern is stronger than the "act on defaults" rule despite memory making it explicit.

### 3. `isActive: null` false-positive

Already captured in memory yesterday after overnight. Team-config liveness fields are unreliable. Dispatched a sibling subagent on a PR thinking the canonical tentacle was dead; it wasn't.

### 4. Trust-without-verify on agent outputs

**New today**: reviewer agent cited two nits (auth scope wrong + dead existsSync import) that did NOT match the actual file. I dispatched a fold to the hub tentacle BEFORE spot-checking the citations. Caught it post-hoc and cancelled the fold — but it cost a dispatch cycle and the tentacle now has churn in its context for no reason.

**Root cause**: my own discipline gap — I was applying "trust but verify" to tentacle commits (checking git log) but not to reviewer findings (just relaying citations without spot-checking them against the file).

### 5. Mental model drift on "who's writing code"

Tentacles see commits authored under Aaron's git identity (since local git config is Aaron's) and conclude "Aaron is typing code." But everyone — tentacles, subagents, Aaron — commits under that same identity. The tentacle's mental model treats commit-authorship as a real concurrency signal when it isn't.

I corrected this twice in-session; the tentacle still drifted back to the dual-actor framing. The rule "you ARE writing these commits, the slot routing makes it look otherwise" doesn't stick.

### 6. Per-PR ceremony shortcuts under load

The full sequence is: reviewer dispatch → fold nits → check gates → merge (or hand off). When work piles up, the ceremony compresses. Today's example: I dispatched the fold without spot-checking the reviewer's citations first. Yesterday: I jumped to subagent dispatch for vault#339 without checking if the tentacle was actually unresponsive.

The shortcuts haven't caused production bugs yet, but they've cost real coordination cycles.

## Why these patterns happen — root causes

**A. Persistence model is leaky.** Tentacles are supposed to be persistent teammates across messages. In practice they: silently die between sends, re-spawn into new slot IDs that don't free old ones, inherit stale cwd, have no reliable liveness signal, generate phantom routing when slots accumulate. The "persistent teammate" framing is doing more work than the underlying machinery supports.

**B. Documentation > behavior gap.** CLAUDE.md and memory are full of "do this, not that" rules. The tentacle reads them and acknowledges them. But under task pressure they revert to default patterns (ask-first, hold-on-uncertainty, narrate-confusion). The corrective rules aren't load-bearing enough to override defaults.

**C. State has too many sources of truth.** For any question ("did C4 land? who's writing? is hub tentacle alive?") there are 3–4 places to look: team config, message channel, working tree, git log. They disagree often. Whichever source the tentacle picks first becomes their narrative, which I then have to contradict.

**D. Memory accumulating without consolidation.** 44 entries. Several overlap (six entries about tentacle dispatch hygiene; four about PR shape; two about "don't wait silently"). Hard to read coherently. New session has to internalize a lot.

**E. Reviewer-as-trusted-source.** I've been treating reviewer agent outputs as authoritative when they're not — they're another LLM call that can hallucinate citations or read stale state. Same trust-but-verify rule that applies to tentacles should apply to reviewers.

## What IS working

Don't throw out:

- **Governance rules** (RC versioning, reviewer dispatch as discipline, merge authority delegation, bundle by session). These have held up under stress; the few corners cut were caught.
- **bun-link development flow** — the running daemon serves whatever's checked out, post-merge sync is mechanical. Friction-free.
- **Memory-as-context-for-future-sessions** — when a memory entry captures a real lesson, it shows up correctly in subsequent sessions and shapes behavior. The system works; it just has too many entries.
- **Single working branch (`ag-unforced-dev`)** — clean, reset-after-merge is reliable, eliminates branch sprawl.
- **Per-repo `CLAUDE.md`** — when a tentacle reads its repo's CLAUDE.md they pick up real conventions. Architecture descriptions are load-bearing.
- **Stacked PRs that accumulate commits** — works correctly when the tentacle commits incrementally. PR review experience is good.
- **The git log is the source of truth.** Tentacle messages, team config, working tree state can all drift. Git log doesn't. This is the reliable signal.
- **Reviewer agent pattern (with verification).** Has caught real issues this session and prior (vault#340 startup log, notes#139 escapeHtml). Today's false-positive was caught by spot-checking. Pattern is worth keeping; my discipline around it needs tightening.

## Options for a cleaner shape

### Option 1 — Subagents as default, tentacles only for genuine iteration

Today: default is "spawn a tentacle per repo, route work via SendMessage."
Reality: tentacles silently die, slot-squat accumulates, dispatching is fragile.

Alternative: spawn a fresh general-purpose subagent for each substantial task. Brief them fully (repo path + conventions + scope + gates + PR shape). They complete synchronously, push commits, return a report. Then they're gone.

Cost: each dispatch needs a comprehensive brief. (We mostly do this anyway — even tentacle re-orientation messages are comprehensive.)
Benefit: predictable lifecycle, no slot phantom, no silent stalls, no dual-actor confusion. The "persistent state across messages" we lose is mostly fictional — tentacles re-orient on every wake-up anyway, so persistence wasn't doing much.

When to keep a tentacle (the narrow remaining case): genuine interactive back-and-forth on a single repo where you're iterating in tight loops (e.g., a long debugging session with the same context). Most of our work doesn't fit that shape.

**My recommendation: Option 1.**

### Option 2 — Keep tentacles, tighten hygiene

- At dispatch, ALWAYS clean dead slots from team config first
- Liveness check via mandatory SendMessage ack before assigning work (don't trust `isActive`)
- Tentacle stands down explicitly via shutdown_response when work is done; team-lead deletes the slot at that moment

Cost: more per-dispatch ceremony.
Benefit: the persistent-teammate framing actually holds.

### Option 3 — Different team granularity

One team per repo instead of one big `parachute-build` team with seven canonical tentacles. Each team has team-lead + that repo's tentacle. Messages can't accidentally route to wrong-repo slots because they don't exist in scope.

Heavier infrastructure but might make slot-squat impossible-by-construction.

## Specific recommendations for the fresh session

If you spin up a new Claude Code session:

### Immediate (5 min)

1. **Clean the team-config** at `~/.claude/teams/parachute-build/config.json` — drop all tentacle slots, keep just team-lead. Fresh start, no phantom routing.

### Before starting real work (30–60 min)

2. **Pick the dispatch model deliberately**:
   - Option 1 (subagent-default) — my recommendation
   - Option 2 (persistent tentacles with tight hygiene) — more familiar but more failure modes

3. **Memory audit and consolidation** — I can do a pass to:
   - Merge `feedback_dont_block_on_silent_input` + `feedback_keep_moving_dont_wait_for_explicit_auth` into one rule about "act-don't-ask"
   - Merge the six tentacle-hygiene entries into ONE comprehensive entry (or retire them if Option 1)
   - Merge `feedback_bundle_*` + `feedback_inline_pr_nits` + `feedback_serial_pr_flow` into one "PR flow practice" entry
   - Add a new entry: "Verify reviewer citations before acting on them"
   - Goal: ~25 consolidated entries instead of 44

4. **Hoist option-A architecture into a design doc** — `parachute.computer/design/2026-05-18-v06-deploy-architecture.md` capturing the single-container hub-as-supervisor decision + disk layout + module install flow. Memory + issues link to it instead of duplicating. Memory should point at canonical docs, not be the canonical doc.

5. **Re-frame the workspace CLAUDE.md "Tentacles" section** to match the chosen dispatch model. If we move to Option 1, the section shrinks dramatically.

### Optional polish

6. **Session-start orientation checklist** in the workspace CLAUDE.md — a clear "first thing you do on entering this directory" sequence (read this CLAUDE.md, read MEMORY.md index, check Current/Parachute MCP, **don't** preemptively spawn tentacles).

7. **Add a memory entry on "verify agent outputs before acting on them"** — covers reviewer citations, research-agent findings, tentacle status claims. Anything an LLM call produces gets spot-checked against ground truth (git log, actual file contents, real test runs).

## Open questions for Aaron

1. **Dispatch model**: Option 1 (subagent-default) or Option 2 (tighter persistent tentacles)? My recommendation is Option 1; happy to argue for it or do it your way.

2. **When does memory audit happen** — at the start of the new session, or end of this one? Doing it now means the new session inherits the cleaned state. Doing it at session start means I can rebuild from current observations.

3. **Design-doc placement**: I propose `parachute.computer/design/2026-05-18-v06-deploy-architecture.md`. Alternative: keep design in `parachute-hub/docs/`. The blog-post-target (parachute.computer/design/) makes it more visible / cited.

4. **What of the current session state should carry over**? hub#262 is in flight (rc.3, ready for your merge). PR will be merged + npm-published in your shell after the new session starts. The tentacle's context is irrelevant to the new session; the git state is.

5. **Anything that's been MORE confusing than I caught?** I'm describing the failure modes I noticed; you may have seen friction I didn't.

## What I'll do without further prompt

After you react to this:

- File a memory entry for the "verify agent outputs" lesson (lightweight, captures today's reviewer false-positive)
- Continue watching hub#262 until you confirm merge
- Stand by for the new session boundary

If you want me to start the memory audit / design doc / CLAUDE.md edits NOW (before the new session), say so. I can also save these for the next session if you'd rather start fresh and have a clean slate.
