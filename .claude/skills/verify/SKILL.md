---
name: verify
description: >-
  The workspace verification discipline — how to prove a change actually works before PR,
  merge, or handoff. TRIGGER when: about to open a PR, about to report gate results, acting
  on a subagent's finding, checking a deploy landed, or running any destructive/lifecycle
  command on a live dev box.
---

# verify — proving it works

The theme: **a claim is verified when you observed the real path, not a proxy for it.**

## Before trusting a verification artifact

**State what it would look like if the thing were broken. If the answer is "the same
thing," it isn't evidence** — true of pass counts (an assertion that stops executing
disappears, it doesn't fail, and the count can even climb as unrelated cases land while
the blind spot holds steady), screenshots (proof of what you looked at, not what's in it
— a "this section rendered" shot can contain the exact bug you're about to miss), and
"green" itself (a skipped suite, a no-op'd job, and a harness that can't observe what it
asserts all report success). Rigor is a property of the harness, not the assertion — a
stricter-looking check can be the vacuous one if the harness can't observe it
(`scrollWidth <= clientWidth` reads as rigorous but is permanently `0/0` under jsdom's
`css: false`; a plain className check was the real signal there).

## Ask what's RUNNING, not what's reported — compare identity, not description

**A version string, a status column, and a git tag all describe intent. Compare artifact
identity instead** — the served asset's hash against the one you just built, the published
tarball's manifest against the source, newest tag against newest npm version. Description
and reality drift silently, and *every* surface signal stays green while they do.

Three instances in one day (2026-07-27/28), each invisible to the obvious check:
- Hub served the app out of bun's install cache — a months-old published version — for nine
  hours, while `parachute status` reported `bun-linked → <repo> @ <sha>`. True of
  *resolution*, false of *what was served*. Caught only by noticing the served
  `/assets/index-<hash>.js` didn't exist in the checkout's `dist/`.
- Five packages had merged-but-unpublished versions (app 4 versions, hub 6 commits, notes-ui
  6 minors, `door-contract` tagged-but-404'd, `account-client` never first-published).
  Nothing asserts **merged == published**, so a *security* bump was merged, tagged,
  changelogged — and in effect nowhere.
- That tagged release had failed at the registry PUT five days earlier. Red run, no alert,
  everyone assumed it shipped. (`dist.attestations` absent on npm ⇒ hand-published ⇒
  probably no Trusted Publishing rule ⇒ its next tag 404s.)

So: fetch the artifact and diff it. `curl` the bundle and check its hash exists in `dist/`;
`npm pack <pkg>@<ver>` and read the tarball rather than the repo; `git ls-remote --tags` vs
`npm view versions`. When a service reports a version, ask **which path did it read that
from** — a cached registration and the bytes on disk are different questions.

Corollary for probes: **grep the URL or the file directly.** A minified bundle is one
~540 KB line; `$(curl …)` + `echo | grep` mangles it and returns false negatives that look
exactly like "the fix isn't deployed."

## Before opening a PR

- Exercise the change end-to-end through the operator's real flow — the bun-linked
  `parachute install`/`start` chain, and for web features the hub-proxied browser path
  (daemon-direct probes are unit checks, not verification). "Tests pass" ≠ "the flow works";
  HTTP 200 ≠ "the page works." State in the PR body what was smoke-tested and what wasn't.
- Run `bun run typecheck` AND the tests, always both — Bun's runtime is lenient where CI's
  `tsc --noEmit` is strict; skipping the 5-second typecheck has burned whole release cycles.
- Read the gate's own verdict line ("Found N errors", "N passed / M failed") — never a blind
  `tail`, which scrolls the summary off AND masks the non-zero exit. Report the runner's
  literal counts (358/359, naming the flake) — never "all green" if anything failed.

## Verifying agent claims

- Treat subagent reports as inputs to verify, not facts. Ground truth is `git show <ref>:<path>`
  and `gh pr diff <n>` — never a working-tree snapshot; agents read stale checkouts.
- Negative findings ("I don't see X") and anything reversing committed work get the most
  scrutiny: verifying costs one command; acting on a false claim costs a reverted commit.

## Live verification

- Chain bugs: bug B is often only reachable once bug A is fixed, so local repros stop at the
  first wall. After 3+ chained fixes, assume more bugs hide behind the latest one — verify on
  the actual deploy after each fix lands.
- A chronically-red gate is a lead, not noise — it launders real regressions as "known red."
  Root-cause it before promoting past it; a gate everyone ignores is worse than no gate.
- When a derived value (key, hash, canonical id) crosses a repo boundary to be COMPARED, send
  the canonical input and derive once on the authority side — two implementations drift, and
  only a real cross-repo call catches it. Per-side unit tests are internally consistent liars.

## Test integrity

- Round-trip/idempotency tests must traverse the serialized form — `f(parse(emit(x))) === f(x)`,
  never `f(x) === f(x)`. Same class: integration tests must exercise the REAL wire shape, not a
  hand-fabricated contract.
- A negative scan ("no secrets found") is vacuous without a positive control — list the scanned
  files and grep for a string known to be present before trusting the clean result.
- Test migrations against real-install fixtures (orphan FKs, mixed-mode rows), not just fresh
  DBs — fresh-DB tests prove it *can* run; fixtures prove it survives the real world.
- When mechanical cleanup (typecheck strictness, migrations) surfaces a real runtime bug, split
  the fix into its own PR — never silence the type error with a literal that preserves the bug.
- **A test that pins an absolute date and then compares against the real clock is a bomb with a
  fuse.** It passes until the fuse burns, then fails forever — and it fails for a reason that has
  nothing to do with the commit that surfaced it. Hub's operator-token test minted at a pinned
  2026-04-26 with a 90-day TTL and validated at real `now`: green until 2026-07-25, red every run
  after. **Inject the clock on BOTH sides**, or mint relative to real now. When triaging one of
  these, sweep for siblings *structurally* rather than by listing date literals — ask which code
  paths enforce expiry against a clock you can't inject (in hub, only jose; everything the hub
  owns takes an injected `now`), then intersect that with pinned mints. That argument bounds the
  class; a list of `new Date("20…")` hits does not.
- **A gate that doesn't run is indistinguishable from a gate that passes.** Know *when* each gate
  last actually executed, not just its last colour. Hub's suite runs at tag time (PR CI is
  container-smoke only), so the bomb above sat red for three days inside a repo that looked
  entirely green; parachute-agent's `main` went red on a **docs-only** commit, meaning the real
  breakage had landed earlier and unobserved. Corollary: **never let a stable release be a line's
  first gate run** — cut an rc, let the gate run, promote on green.
- **Watch a new test fail before believing it.** Revert the fix (or stub the subject out), keep
  the test, confirm it goes red *for the stated reason* — then restore. A test never seen failing
  is an untested assertion. Two catches in one night: a pager test that passed on broken code,
  and the sentinel below.
- **A sentinel must match the signature of the thing it guards — not a channel that thing merely
  shares.** `expect(fetch).toHaveBeenCalled()` before asserting "no band rendered" guards *"a
  fetch happened"*, and the probe shares `fetch` with three other callers — so the guard held
  with the probe deleted entirely. Fix: match a discriminating signature (`exclude_tag=guide`).
  **The tell:** a guard that only has to *notice* a signal can be satisfied by any traffic on the
  shared channel; one that has to *count* a specific signal is forced to name it. So **assert a
  quantity or identity of the specific signal, not the presence of a shared side-effect** — and
  apply the litmus above: delete the subject, confirm the guard fails.

## Test at the scale the thing will actually meet

Every fixture and sandbox we build defaults to ~15 notes and 3–4 tags. Real vaults have dozens of
tags and thousands of notes, and code that looks correct at the first scale can be catastrophically
wrong at the second — **it fails by working, then failing later**, which no unit test catches.

Three bugs shipped in one night for exactly this reason: a filter panel that hid its own results,
a tag page that rendered 622 rows into a 64,000px document, and an All-notes list whose pager
buttons could never enable because a live subscription silently replaced the paged window with
the entire vault.

So: **run it against the repo's realistic-scale fixture before shipping** — each repo owns its
own and states the trigger in its `CLAUDE.md` (parachute-app's is `bun run bigvault up`). The
fixture must be deterministic, or a before/after comparison proves nothing. And prefer a measured
before/after table — DOM rows, page height, bytes on the wire, cold time-to-interactive — over an
assertion that it "feels fine."

## Environment safety — hard rules

- **Never run destructive CLI (`migrate`, `init`, `expose`, uninstall/lifecycle) against the
  live `~/.parachute`.** Sandbox in a fresh `PARACHUTE_HOME=/tmp/parachute-test-$$` and run
  `bun src/cli.ts …` from the checkout — it never touches the bun-linked binary.
- **Never run the hub suite (`bun test ./src`) on a live box** until the launchctl-touching
  tests are confirmed stubbed — the launchd label is hardcoded and ignores both `PARACHUTE_HOME`
  and worktrees; a lifecycle test has bootout'd the real hub and taken the whole ecosystem down.
