# Parachute — handoff for an incoming dev agent

Written 2026-07-31 at the end of a long session. Assumes you can read the repos;
this covers what the code *doesn't* tell you — what's in flight, what's decided,
what's still open, and the traps that cost real time.

**Read `CLAUDE.md` at the workspace root first**, then this. It has the process
rules; this has the current state.

---

## 1. Where things stand

The arc of this session: **make self-hosting as simple as the cloud experience.**
That was Aaron's framing, and it's the lens for everything below.

Shipped (all merged unless noted):

- **The app is the front door.** `/` serves the app at the origin root. This
  matters more than it sounds — the app's bundle is built for the origin root
  (absolute `/assets/*`, PWA scope `/`), and an earlier decision to redirect `/`
  → `/app` produced four separate bugs before the root cause was found. Note
  URLs now match the hosted door exactly: `/n/<id>` on both.
- **Transcription moved into the vault.** whisper.cpp + Parakeet/Whisper models,
  installed and *verified transcribing* by `parachute-vault transcription
  install`. Scribe is retired.
- **Git import is an async job** with a stall timer, not a 60s wall-clock cap.
- **OAuth consent is per-scope**, with risk tiers and account scopes that are
  requestable but capped and unadvertised.
- **One setup script** for Mac and Linux (`parachute.computer/install/parachute.sh`),
  validated end-to-end on a real DigitalOcean box.

In flight at handoff:

- **hub#816** — promote `0.7.12` to `@latest`. **hub#814 (rc.3) is superseded;
  close it unmerged.**
- **parachute.computer#180** — Caddyfile marker + installer idempotency.

---

## 2. The single most useful habit

**Verify before you report, and verify the thing itself rather than a proxy.**

Real examples from this session, all of which cost time or shipped bugs:

- A test asserted the setup wizard installs scribe, and **passed** after scribe
  was retired. The retirement and the bypass were each internally consistent, so
  nothing contradicted anything. Found only by tracing callers.
- A CI failure blocked *every release for four merges* because a test passed
  locally (the app package happened to be installed) and failed in CI. Green
  locally is not green.
- An installer idempotency check was written as a grep against CLI output —
  and matched nothing, because the line it looked for only existed in an
  unreleased version. It would have been a silent no-op that looked like a
  feature.
- A diagnosis "confirmed" by running tests with `-t` against what was believed
  to be `main` — but the working tree already had the commit, so it compared
  against itself.

The pattern in all four: **the check agreed with the code instead of testing
it.** When you write a guard, mutate the thing it guards and confirm it fails.

---

## 3. Traps that will cost you a day

- **`@rc` can be BEHIND `@latest`.** If trains ship stable-direct, the rc
  dist-tag goes stale and `bun add -g <pkg>@rc` is a *downgrade*. This happened
  live: a box went hub 0.7.11 → 0.7.9-rc.6 and reinstated a fixed bug.
  `parachute upgrade` survives it (best-of resolution); a raw `bun add -g` does
  not.
- **A module's channel belongs in the persisted `module_install_channel`
  setting**, not a one-off install. A raw install leaves the setting untouched
  and the next `parachute install` silently pulls stable.
- **Half-removals are the recurring failure mode.** Removing a `services.json`
  row but leaving the npm package meant scribe *reappeared* — services own the
  write side of that file, so anything that runs re-registers. `parachute
  uninstall` does all four steps; hand-editing does not.
- **Never run `biome` in `parachute-vault`.** It has no config; `--write`
  reformats 332 files. Biome is hub-only.
- **`bun test src` vs `bun test ./src`** — without `./` it picks up
  `packages/scope-guard/` too and inflates counts.
- **`curl | bash` means stdin is the pipe.** Any prompt in an install path
  either hangs or eats a line of the script as its answer. `parachute init` has
  an interactive exposure prompt — pass `--no-expose-prompt`.
- **launchd doesn't inherit login-shell PATH.** A binary can be installed and
  invisible to a supervised process. That's why transcription surfaces report
  *which directories were searched*, not just "not found".

---

## 4. Decisions that are settled — don't relitigate without a reason

- **Stable is a judgement that a train is good, not a delivery mechanism.** If a
  box needs a fix, cut an rc and point the box at `@rc`. Four stable releases
  shipped in one evening because a box tracked `@latest`, and one put a broken
  front door on `@latest`. Written up in `docs/process/governance.md`.
- **Feature PRs don't touch the version or CHANGELOG.** A release PR does.
  This exists because shared-line edits made every merge conflict every other
  open PR.
- **Account scopes are requestable but NOT advertised.** RFC 8414 §2 and RFC
  9728 §2 both permit this, and MCP's 2025-11-25 spec says `scopes_supported`
  should be the *minimal* set. Clients request the whole advertised catalog —
  with account scopes listed, a note-taking app asked for permanent delete
  across every vault. Discovery happens at the point of refusal via the RFC 6750
  `scope` challenge parameter.
- **Scribe's retirement is graceful, not a deletion.** The registry entry stays
  so an existing `services.json` row is still startable; `selfHealScribeAuth`
  still runs every boot; `unwireScribeAuth` still runs on uninstall. Only *new*
  installs are refused.
- **The browser wizard does NOT get a transcription control.** The vault admin's
  Transcription page is the browser-native surface. A hub-side control would run
  a multi-hundred-MB download inside the vault-install op and be a second, worse
  UI for a vault-owned operation.

---

## 5. Open work, roughly in priority order

### 5.1 Root `/mcp` — designed, not built

The most substantial open item. An external team (hive/Buzz) reported that root
`/mcp` "binds to one vault" and that RFC 8707 `resource=` doesn't narrow the
audience. **Both their read and the obvious fix were partly wrong** — a design
pass established:

- `/mcp` is *not* single-vault. Vault derives the target from the token
  (`parachute-vault/src/routing.ts`, `deriveVaultFromToken` in `auth.ts`) and
  re-dispatches through the per-vault machinery with the audience pin intact.
  `serverInfo: parachute-vault/unforced` is the *token-derived* vault — it looks
  hardcoded only because there's one vault on that box.
- The same token working at both `/mcp` and `/vault/<name>/mcp` is **correct by
  design**, not replay. Cross-vault replay is blocked twice (`aud` mismatch in
  scope-guard, plus `vault_scope`).
- The real gap: `resolveResourceVault` (`parachute-hub/src/resource-binding.ts`)
  recognises only per-vault resource shapes, so root `/mcp` falls through with
  no narrowing. **"Add it to the resolvable set" is not the fix** — there's no
  vault name in that path to narrow *to*. It needs an explicit root branch.
- Separately: `/oauth/token` ignores `resource` entirely.

**Before changing anything, run the two-vault test.** Create a second vault,
mint a token scoped to the first, and probe: `T-alpha → /vault/beta/mcp` must
401 with `audience mismatch`. If it returns 200, that's a genuine cross-vault
vulnerability and the analysis above is wrong. Per the code it cannot — but that
probe is the point.

### 5.2 Retire `server.sh`

`parachute.computer/install/parachute.sh` is the unified installer and works
end-to-end on a real box. `server.sh` is still served because it writes a
bootstrap token to a file that the unattended/IaC path documents reading over
SSH — `parachute.sh` doesn't reproduce that yet. Port it, verify on a fresh VPS,
then make `server.sh` an alias.

### 5.3 The install-tile machinery

`INSTALL_TILE_PROPS` in `setup-wizard.ts` now has no live tenant. A design pass
recommended deleting the whole generic machinery; I kept it deliberately, on the
grounds that it isn't module-specific and deleting a generic capability because
its config is momentarily empty is a different call from deleting dead
module code. If it should go, that's its own diff with its own argument.

### 5.4 Long-lived credentials for unattended clients

Offered by the hive team, not filed as a bug: 15-minute access tokens are
hostile to any client that captures a credential once for a long-lived
connection (ACP's MCP transport does exactly that). They solved it their side.
If unattended agents become a common way people reach Parachute, either a
longer-lived credential for confidential clients or documenting "your client
must be able to re-acquire mid-session" would remove a sharp edge. **Product
call, not a bug fix.**

### 5.5 Explicitly NOT to build

The hive team **retracted** their `token_expired` vs `unauthorized` finding —
the evidence was their agent's own unauthenticated `curl` plus a confabulated
statement. Don't build it on the strength of that report. If it's wanted, it
needs its own motivation.

---

## 6. Working with the hive/Buzz team

They report carefully, version-pin their observations, and retract when wrong —
their correction document was better than the original report. Treat their
findings as high-signal, and **check npm before telling them a build exists.**
That mistake was made once here: a release was announced that had never
published, because a CI failure had silently blocked it.

---

## 7. Practicalities

- All work goes via `unforcedagi` forks and PRs; **Aaron merges.** No push
  access to `ParachuteComputer/*`.
- Branch work belongs in a **worktree** — the checkout is what `parachute start`
  serves, and a restart can be triggered by anyone.
- Every PR gets an independent review before merge
  (`.claude/skills/review-subagents/`).
- Fable planning agents were genuinely valuable here: one found a shipped bug in
  a diff that tests passed on, another corrected a wrong framing of the root
  `/mcp` problem, a third established that the scope-discovery posture was
  standards-endorsed rather than a hack. Use them for design and
  callers-tracing; do the mechanical work yourself.
