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
