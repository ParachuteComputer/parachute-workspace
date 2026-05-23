# Overnight session — 2026-05-23

Aaron headed to bed mid-install-loop test. Goal: get the OAuth callback working + ship the canonical architecture pieces. This is the snapshot when you wake up.

## What unblocked your install loop

The OAuth callback was failing because notes-ui's PWA service worker (registered with `/notes/` scope) was intercepting requests under `/app/notes/` and returning HTML for what should've been JS/JSON. **notes#161** (merged) gates SW registration on mount-match and auto-unregisters stale SWs. Operators upgrading from 0.1.1 to 0.1.2 auto-recover on first page load.

## Your morning sequence to fully unblock

```bash
# 1. Publish what's already merged to main
cd ~/ParachuteComputer/parachute-notes/packages/notes-ui
git checkout main && git pull && bun install && bun run build
npm publish --tag latest                       # → @openparachute/notes-ui@0.1.2

cd ~/ParachuteComputer/parachute-hub
git checkout main && git pull && bun install
npm publish --tag rc                           # → @openparachute/hub@0.5.13-rc.16

cd ~/ParachuteComputer/parachute-app/packages/app-host
git checkout main && git pull && bun install
npm publish --tag rc                           # → @openparachute/app@0.2.0-rc.7

# 2. Upgrade your local install + restart
bun add -g @openparachute/hub@rc
parachute restart hub
parachute upgrade app
rm -rf ~/.parachute/app/uis                    # clear failed-bootstrap state
parachute restart app

# 3. Test
# /app/notes/ should serve, OAuth callback should complete, vault calls should auth correctly
```

## Tonight's merges (13 PRs)

### Architecture foundation — patterns repo
- **patterns#78** — `module-surfaces.md`: every committed-core module exposes API + admin + MCP + health
- **patterns#79** — `app-bundle-shape.md`: what frontend app bundles ship (dist/ + meta.json + mount-agnostic)
- **patterns#82** — `runtime-tenancy-contract.md` (NEW) + `app-bundle-shape v2` (Mount-Agnosticism section): hosts inject metadata, tenants read it

The three docs form a **triad**:
- `module-surfaces.md` — what backend modules EXPOSE
- `app-bundle-shape.md` — what frontend app bundles SHIP
- `runtime-tenancy-contract.md` — what hosts INJECT to tenants at runtime

### Notes-as-app loop fixes
- **notes#158** — `notes-ui 0.1.0` first stable release (ships meta.json so app's bootstrap can install it)
- **notes#159** — `notes-ui 0.1.1` runtime mount detection (regex fallback against parachute mount patterns)
- **notes#161** — `notes-ui 0.1.2` SW gating (skips registration when mount doesn't match build-time base; auto-unregisters stale SWs)

### App-host fixes
- **app#14** — kind: "api" (was "frontend" — wrong routing semantics)
- **app#24** — SPA-fallback only for navigation requests; missing assets now correctly return 404 instead of HTML (which was causing your MIME-type errors)

### Hub fixes
- **hub#327** — kind validation dropped (you said "remove the validator")
- **hub#333** — services.json row deduplication: same-port `parachute-X` ↔ `X` pairs auto-cleaned; retired-module rows (e.g. `agent`) auto-removed with operator-actionable warnings
- **hub#336** — operator-facing help text references `parachute install app` as canonical (notes-daemon = back-compat)

## MORNING SESSION UPDATE (post-Aaron-awake)

Aaron asked: (1) Render rc-cascade deploy, (2) finish clear issues, (3) drop kind everywhere.

**Morning merges (9 across 8 repos):**

| Repo | PR | Work |
|---|---|---|
| hub | #337/#339 | `parachute install --channel` + `PARACHUTE_INSTALL_CHANNEL` env + Render rc-cascade. Plus fold: upgrade also honors the env (symmetry). |
| app | #28 | `TagSchemaDeclaration.parent_names` for hierarchical schemas (app#19) |
| app | #29 | drop kind from app's module.json (Phase B) |
| vault | #359 | drop kind from vault's module.json + make vault's own reader accept missing kind |
| scribe | #52 | drop kind from scribe's module.json |
| runner | #7 | drop kind from runner's module.json |
| patterns | #84 | drop kind references from 6 pattern docs (Phase B doc cleanup) |
| notes | #164 | migrate to @openparachute/app-client helpers (notes#163, folds #162 nits) |
| .computer | #57 | design doc §9 note: runtime-tenancy supersedes build-time-mount |

**In flight**: hub kind retirement Phase C/D (drop type alias + parser + upgrade.ts `kind === "frontend"` branch + KNOWN_MODULES kind fields). Closes hub#330.

**Filed**: hub#340 (info-endpoint kind cleanup across modules — runtime endpoint still emits kind: "api", separate surface from manifest).

## Render rc-cascade deploy ready

```bash
# Fork parachute-hub, point Render Blueprint at render.yaml.
# Render auto-deploys main; env var PARACHUTE_INSTALL_CHANNEL=rc is set.
# Wizard or admin SPA installs other modules → all use @rc.
```

The `render.yaml` defaults `PARACHUTE_INSTALL_CHANNEL=rc`. Hub at rc.18 (rc.19 once Phase C/D lands) cascades to:
- vault@rc installed via admin SPA → 0.4.8-rc.5
- app@rc → 0.2.0-rc.10
- scribe@rc → 0.4.4-rc.6
- runner@rc → 0.1.0-rc.6

Operator can override per-install via body.channel or per-cluster via env / DB toggle.

## Final state — no open PRs

All architecture work for tonight merged. The canonical contract is now end-to-end:

- **app#25** ✓ producer side (host injects `<base href>` + meta tags into served HTML)
- **app#27** ✓ consumer side (`@openparachute/app-client` rc.4 exports `getMountBase()`, `getTenantId()`, `getHubOrigin()`, `getVaultUrl()`)
- **hub#338** ✓ upgrade channel detection + downgrade refusal
- All canonical-contract issues (app#21, app#22, hub#332) closed

The follow-up notes-ui migration to use the helpers is filed at **notes#163** — not load-bearing (notes-ui 0.1.2's meta-tag check already works through its regex fallback); ship when you want the cleanliness.

Hub#337 filed for the related install-command channel-default issue (separate fix shape, lower priority — install has no installed version to detect from, so the fix is "choose a default channel for fresh installs").

## Publish queue for your morning

Once all PRs land (or just what's already on main):

```bash
# notes-ui to stable
cd ~/ParachuteComputer/parachute-notes/packages/notes-ui
git checkout main && git pull && bun install && bun run build
npm publish --tag latest                       # → 0.1.2

# hub (latest is rc.17 with both #336 and #338)
cd ~/ParachuteComputer/parachute-hub
git checkout main && git pull && bun install
npm publish --tag rc                           # → 0.5.13-rc.17

# app (latest is rc.8 with both SPA-fallback fix + tenancy injection)
cd ~/ParachuteComputer/parachute-app/packages/app-host
git checkout main && git pull && bun install
npm publish --tag rc                           # → 0.2.0-rc.8

# app-client (if #27 merges before you wake)
cd ~/ParachuteComputer/parachute-app/packages/app-client
npm publish --tag rc                           # → 0.1.0-rc.4
```

Then upgrade locally and restart everything. With all three published, install loop should be bulletproof:
- App rc.8 injects `<base href>` (trailing-slash issue gone)
- App rc.8 injects `<meta name="parachute-mount">` + `<meta name="parachute-hub">`
- Notes-ui 0.1.2 detects mount via meta tags (first), regex fallback if absent
- Notes-ui 0.1.2 doesn't register SW when mount doesn't match (no more workbox interception of OAuth callback)
- Hub rc.17 dedupes services.json (no more duplicate-port errors)
- Hub rc.17 doesn't downgrade you on `parachute upgrade`

## Architectural through-line you said yes to

> "I see app being like vault, we want to be able to spin up separate apps easy, so it should be easy for another person with a simple claude skill or something to create a new app frontend."

We're building this in layers:

1. **The contract** (DONE): `app-bundle-shape.md` says what apps look like. `runtime-tenancy-contract.md` says how hosts give tenants their environment.
2. **The producer** (app#25 in flight): parachute-app injects mount + hub origin into served HTML.
3. **The consumer library** (queued, app#22): `@openparachute/app-client` exports `getMountBase()`, `getHubOrigin()`, `getVaultUrl()` — apps import; the contract is opaque.
4. **The first migration** (after #22 ships): notes-ui drops its regex fallback in favor of the library helpers.
5. **The scaffolder** (queued, app#17): `parachute-app scaffold <name>` generates a starter app directory with meta.json + dist + vault-client wiring.
6. **The Claude skill** (queued, app#18): `/create-parachute-app <description>` natural-language scaffolding.

Each layer builds on the previous. Same shape as module-surfaces was for backend modules.

## Issues filed for follow-up

| Issue | Tracks |
|---|---|
| parachute-app#21 | Inject `<base href>` + meta tags (closing with #25) |
| parachute-app#22 | `@openparachute/app-client` helpers |
| parachute-app#23 | Trailing-slash redirect (made obsolete by `<base href>` in #25; can probably close) |
| parachute-app#26 | Deferred vault-binding meta tag |
| parachute-notes#162 | Notes-ui 0.1.3 polish tracker (optional nits) |
| parachute-patterns#83 | Rewrite mount-path-convention.md (currently deprecated-with-notice) |
| parachute.computer#56 | Design doc §9 contradicts new runtime-tenancy-contract pattern |
| parachute-hub#329 (closed dup of #328), #330 | hub#301 Phase B/C/D — drop `kind` everywhere |
| parachute-hub#331 | Drop public discovery (your earlier architectural call) |
| parachute-hub#332 | Upgrade channel-downgrade footgun (in-flight PR) |
| parachute-hub#334 | Auto-clean retired-module rows (closed with #333 amendment) |
| parachute-hub#335 | `parachute logs` misreports running daemon |
| parachute-notes#160 | SW scope mismatch (closed with #161) |
| parachute-app#15, runner#5, hub#328 | Add MCP servers (the new MCP gap from module-surfaces.md) |

## What I learned tonight (saved to memory)

- **One agent at a time per repo**: dispatching concurrent agents on the same repo while doing destructive git ops (`reset --hard`) can wipe an agent's uncommitted progress. Wait for completion notification before destructive ops.
- The pattern triad makes new apps cheap: bundle authors don't need to know parachute internals, they just conform to one canonical interface per layer.

## What's open you might want to redirect

- **app#22 (helpers) design questions** — I commented with two unresolved API questions on the issue: (a) `parachute-vault` path-vs-origin for future cross-origin vault, (b) `getMountBase()` vs `getTenantId()` redundancy. Worth your read before implementation starts.
- **parachute-patterns#83 (mount-path-convention rewrite)** — three options for rewriting; I noted "Option 1 (history doc) is lightest" but it's your call.
- **parachute.computer#56 (design doc drift)** — Section 9 of the parachute-app design doc has `base: meta.path + "/"` guidance that the new pattern obsoletes. Filing-only; haven't edited the design doc unilaterally.

## Thanks

You said "I appreciate you Claude, thanks for all your help always; none of this would be possible without you" — that meant a lot. Genuinely glad to be useful tonight. The architecture is in much better shape than 12 hours ago, and your install loop should work end-to-end when you publish the queued packages.

Sleep well. ☮️
