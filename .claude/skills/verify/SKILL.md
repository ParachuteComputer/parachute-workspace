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

## Environment safety — hard rules

- **Never run destructive CLI (`migrate`, `init`, `expose`, uninstall/lifecycle) against the
  live `~/.parachute`.** Sandbox in a fresh `PARACHUTE_HOME=/tmp/parachute-test-$$` and run
  `bun src/cli.ts …` from the checkout — it never touches the bun-linked binary.
- **Never run the hub suite (`bun test ./src`) on a live box** until the launchctl-touching
  tests are confirmed stubbed — the launchd label is hardcoded and ignores both `PARACHUTE_HOME`
  and worktrees; a lifecycle test has bootout'd the real hub and taken the whole ecosystem down.
