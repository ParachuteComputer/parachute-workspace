# Thinking-doc — multi-user UX + cloud-hosting strategy

Working doc for two strategic threads Aaron flagged 2026-05-17. Treat this as a sketch for dialogue, not a plan. Both threads are pre-v0.5 commitment but post-v0.5 substantive build.

## Thread 1 — Multi-user UX

### Where we are

- **Hub-as-AS works**: hub#212 Phases 0-A all shipped. JWTs minted from hub, scope-narrowing real, revocation enforcement live.
- **Scope-guard package** validates hub-signed JWTs at resource servers (vault, notes, scribe, future agent).
- **What's MISSING is the surface**: sign-in flows, user-management UI, consent surfaces. Tracked at hub#252.
- Today's practical multi-writer pattern: each writer (human or agent) gets their own hub-issued JWT via `parachute-vault tokens create` or the admin SPA. Bridging — operator does it.

### The user journey we want

Imagine a 3-person org (Mathilda runs campaigns, Kevin captures from mobile, Ash drafts longform):

1. **Hub deployed** — somewhere accessible to all three. Render/Railway/self-host (see Thread 2).
2. **First admin** (Aaron-shaped) sets up hub via `parachute setup`. Becomes the user-management surface.
3. **Invites** — admin generates an invite link or shares an org code. New user opens hub URL → sign-in/sign-up flow.
4. **Sign-in** — password? OAuth-via-hub-issuer (i.e., hub IS the IdP)? Magic links?
5. **Scope assignment** — admin assigns Mathilda to `vault:donor-pipeline:write`, Kevin to `vault:capture:write`, Ash to `vault:storyboard:write`.
6. **Per-user surface** — each opens hub URL, sees their stuff. Notes PWA picks up their identity. MCP integrations attribute writes correctly.

### What's blocked today

| Step | Status | Blocker |
|---|---|---|
| Hub deployed | ✓ | Just needs deploy story (Thread 2) |
| First admin setup | ✓ | `parachute setup` works for single-admin |
| Invites | ❌ | No UI, no flow |
| Sign-in | ❌ | Login form exists for the single admin user; multi-user not modeled |
| Scope assignment | partial | Admin SPA can mint tokens; no per-user view |
| Per-user surface | partial | Notes PWA holds hub-issued JWT in localStorage; works per-identity but no concept of "the same person across devices" |

### Decisions to make

**A. Identity primitive.** Today: hub-account = 1 admin. To support N users: 
- **Native users table** in hub's DB (rows: username, password-hash, 2fa, role).
- **OR** integrate an existing IdP (Auth0, Clerk, Google) — but that adds an external dependency to the self-hosted story.
- **Recommend**: native users table. Lock-in to hub-as-IdP. Future option: bridge to external IdPs later as a plug.

**B. Sign-in flow shape.**
- **Password + 2FA**: most familiar. Friction: account recovery hard for self-hosted.
- **Magic-link**: lower friction. Needs email config — adds setup cost.
- **OAuth-with-passkey**: lowest friction, most modern. Bigger build.
- **Recommend**: password + 2FA for v0.6, magic-link as v0.7 option (when email infra is figured out).

**C. Invite flow.**
- **Admin-generated link** (the user opens it, signs up): simple, doesn't need email.
- **Admin-enters-email + system-sends-invite**: needs email config.
- **Recommend**: invite-links for v0.6. Email integration as v0.7.

**D. Per-user scope model.**
- Today: tokens have `scoped_tags: ["tag-prefix-list"]`.
- Multi-user extension: users have an `allowed_tags` set; when they mint a token (or hub mints on their behalf), the token's scope intersects with their allowed set.
- Admin UI: per-user table showing which tags they can write.

**E. Per-identity attribution on notes.** Vault#298 tracks this — when a note is created/updated, record which hub-identity did it. Notes UI shows "Updated by Mathilda 5min ago." Today: only the hub `sub` claim is read for auth, then discarded.

### Phasing for v0.6

**Phase 1 (v0.6.0)** — Multi-user foundation:
- Users table in hub
- Sign-in (password + 2FA) + sign-up via invite link
- Admin SPA gains user-management surface
- Per-user scope assignment

**Phase 2 (v0.6.1)** — Attribution + surfaces:
- Per-identity attribution column on vault.notes (vault#298)
- Notes UI shows the attribution
- Consent screens for MCP-client OAuth flows mention which user is authorizing

**Phase 3 (v0.7+)** — Email + advanced:
- Email infrastructure (SES / Resend / SMTP)
- Magic-link invites + login
- Password reset via email
- Audit log per user

### Pre-v0.6 — what to land now

- **Filed: hub#252** captures the design surface.
- **Scaffolding could begin in v0.5 cycle** — users table migration, basic password flow behind a feature flag. Lets us land the foundation without committing to public-facing UX.

## Thread 2 — Cloud-hosting strategy

### Where we are

- **Self-hosting works** for someone willing to install bun + run `parachute setup` on a Mac / Linux box / VPS.
- **One-click deployment** does NOT exist. Render / Railway / Hetzner all require manual setup.
- **Our own hosted offering** — design sketch lives in `parachute.computer/design/2026-04-20-cloud-offering-sketch.md`. Not built.

### What "easy self-host" looks like

Goal: a non-technical user can deploy hub + vault to their own infrastructure in <10min, with a credit card and a domain.

Two paths:

**A. Render / Railway / Vercel-style one-click**

Render and Railway both support "deploy from GitHub" with a `render.yaml` / `railway.toml` config. The config declares: services, env vars, ports, persistent storage.

For Parachute, that means:
- A `render.yaml` in the parachute-hub repo (or a new `parachute-deploy` repo) that:
  - Spawns a hub container
  - Spawns a vault container
  - Mounts persistent disk for `~/.parachute/`
  - Wires DNS / SSL via Render's domain layer
  - Exposes the hub on a public URL

**Blockers today**:
- No Dockerfile for hub or vault (we run `bun src/cli.ts` locally, not in a container).
- `~/.parachute/` is a local concept; needs to map to a persistent volume.
- The "one URL" model — hub serves all services on path-prefixes (`/notes`, `/vault/<name>`). On Render that's one service with internal routing.
- TLS / domain config — Render handles this; just need declarative wiring.

**Effort**: substantial first time (~1 week of build), then `render.yaml` becomes the artifact users consume. Tracks at... no issue exists yet. Should file.

**B. Hetzner / DigitalOcean / Vultr-style VPS one-liner**

For users wanting their own VPS (control, cost, location):
- A `parachute-self-host.sh` script that takes a fresh VPS + a domain → fully working install in <5min.
- Or: a Docker Compose file that does the same locally.

**Blockers**: same as above (Dockerfile, persistent volume, TLS via Caddy/Traefik). Plus: domain wiring is manual on a VPS.

**Effort**: similar Dockerfile work, then a shell script. Could come AFTER Render path lands.

### Our own hosted offering

What it would mean:
- `parachute.cloud` (or similar) — a hosted version of Parachute. User signs up, gets a vault, MCP token, Notes PWA URL.
- Multi-tenant hub: one hub serves many users' vaults.
- We run the infrastructure; user pays.

**Design sketch** (`parachute.computer/design/2026-04-20-cloud-offering-sketch.md`) covers this in some depth — should re-read it. Last touched 2026-04-20; probably stale relative to recent vault work but still directionally useful.

**Significant build**:
- Multi-tenant hub (one process, N user-tagged vaults). Today's hub is single-tenant.
- Vault isolation: each user's notes are in a separate SQLite DB, or one DB with row-level scoping.
- Billing infrastructure (Stripe).
- Sign-up flow (which depends on multi-user UX from Thread 1).
- TLS + domain (cloud-shape work).
- Backup / monitoring / on-call.

**Sequencing**: Self-host first (a one-click deploy gives anyone who wants to self-host the option). Then own-hosted as a "we run it for you" tier.

### Phasing for the cloud arc

**Phase 1 (post-v0.5)** — Easy self-host on Render/Railway:
- Dockerfile for hub + vault
- `render.yaml` declarative config
- Persistent volume mapping
- Domain + TLS auto-config
- Documentation: "Deploy Parachute to Render in 5 minutes"

**Phase 2 (post-v0.6)** — Easy self-host on VPS:
- `parachute-self-host` script for VPS
- Docker Compose for local LAN deployments
- Backup / restore docs

**Phase 3 (post-v0.7?)** — Our own hosted offering:
- Multi-tenant hub (depends on multi-user UX from Thread 1)
- Sign-up + billing
- Operational tooling (monitoring, backups, support)

### Coordination with Thread 1

Multi-user UX (Thread 1) is a **prerequisite** for our own hosted offering. The hosted offering is just "multi-user hub at scale, operated by us."

But: multi-user UX is INDEPENDENTLY valuable for self-hosters (Mathilda+Kevin+Ash on Aaron's self-hosted instance). So Thread 1 can ship before Thread 2's full stack lands.

## Suggested first concrete steps

To start moving on both threads without waiting for v0.5 to ship:

1. **Re-read the cloud-offering-sketch design doc** and either refresh it or supersede it with a new doc reflecting current architecture (post vault#308, post hub-as-AS).
2. **File a tracking issue per phase** so we can dispatch work as bandwidth allows:
   - hub-or-deploy issue: "Render/Railway one-click deploy" (depends on Dockerfile)
   - hub issue: "Dockerfile + bun-in-container shape" (Dockerfile + persistent vol mapping)
   - hub issue (extends #252): "Multi-user Phase 1 — users table + sign-in (password)"
   - hub issue: "Multi-user Phase 2 — user-management SPA surface"
3. **Light scaffolding work** can start in v0.5 cycle behind feature flags. Users table migration can land; sign-in UI behind a flag.

## Aaron's answers (2026-05-17 / 18)

1. **Multi-user**: native users table in hub. (External IdP integration not the path.)
2. **Cloud self-host**: Render is the primary target.
3. **Own-hosted offering**: <1 month. Closed-beta-ready in ~3 weeks is realistic; public-with-billing in ~6.
4. **Hub split**: deferred — not thinking that far ahead yet.
5. **Self-host one-click**: lives in `parachute-hub` (Dockerfile + render.yaml in repo root, not a separate `@openparachute/deploy` repo).

## Plus broader direction (2026-05-18)

- **First-boot wizard is YES** — web-based, not env-var.
- **"No command line for management"** — admin UI grows from "first-boot wizard" into a fuller surface: install modules / upgrade modules / configure modules — all via web.
- **Per-service Render disks** — ~~yes (failure isolation)~~ SUPERSEDED by single-container option A below.
- **Notes served by hub** — yes (simpler).

## Architecture pivot (2026-05-18, late) — option A locked in

After flagging that multi-container = $7 × N (Render bills per service, not per account), Aaron rejected the multi-container shape: "if we're paying $7 for each one that is not an acceptable orientation."

**Reconsidered. Locked in option A: single Render container running hub-as-supervisor.**

This is the **deploy mirror of the local model**. Locally, `parachute serve` runs hub, hub spawns vault/notes/scribe as children, all share `~/.parachute/`. Cloud is the same process group, in a container.

### Why this works

- **Cost**: $7/mo Starter regardless of module count. Modular pricing preserved.
- **UX**: friend sees one Deploy button, one URL, one disk, one bill. No cross-service wiring.
- **No new orchestration**: hub-as-supervisor already runs in production locally. We don't invent anything new.
- **Modules stay modular at the CODE level** — separate repos, versions, deps. They just share an OS process group at runtime. Same as e.g. Forgejo (one binary, many features).

### Trade-off acknowledged

Shared process means one module's OOM affects all. Mitigation: hub supervises with restart-on-crash; Render Starter has 512MB which fits hub + vault + notes comfortably at v0.6 scale. Per-service splits possible later when a real user hits the limit.

### What changes from earlier multi-container thinking

- **No multi-service render.yaml**: hub's render.yaml stays single-service.
- **Vault Dockerfile + render.yaml from vault#339**: Dockerfile stays useful (CI, future hub-spawns-vault-image flows). Standalone render.yaml deprecated as primary path — filing vault followup.
- **hub#260 (admin module mgmt UI)**: PROMOTED to Phase 1 critical-path. Was Phase 2. Without it, deployed hub is stuck empty — friend can't install vault/notes/scribe.
- **Runtime module install**: hub#260 includes the `BUN_INSTALL=/parachute/modules` pattern so installed modules persist on the disk (not the ephemeral image layer). Container restart → hub reads services.json → re-spawns each registered module from `/parachute/modules/node_modules/`.

### v0.6 release bar (Aaron 2026-05-18)

**No partial ship.** v0.6 ships only when a friend can fork + click Deploy + install vault + notes + scribe from the web UI in <5min, all working. The bar is the complete friend-experience loop.

### Issues reshaped

- **hub#257** (meta-tracker) — Phase 1/2/3 reshaped per option A
- **hub#258** (Dockerfile + render.yaml) — done; no change
- **hub#259** (first-boot wizard) — refined: vault install in wizard step 3 calls the hub#260 module-install API rather than a special seam
- **hub#260** (admin module mgmt UI) — PROMOTED Phase 1; includes BUN_INSTALL container-mode design notes, supervised-children-in-container behaviors, log multiplexing
- **vault#339** — Dockerfile retained; standalone render.yaml deprecated (vault-side followup filed)
- **parachute.computer#42** (/deploy page) — single Deploy button, hub-only target, modules installed post-deploy via admin SPA

## Issues filed (2026-05-18)

- **hub#257** — meta-tracker for v0.6 Render self-host milestone
- **hub#258** — Dockerfile + render.yaml + env-driven boot
- **hub#259** — first-boot web wizard at /admin/setup
- **hub#260** — admin SPA module management (install/upgrade/configure via UI)
- **vault#339** — vault Dockerfile + cross-service-auth for non-loopback
- **parachute.computer#42** — /deploy page on parachute.computer

## Suggested first dispatches (no urgency)

1. **hub#258** (Dockerfile + render.yaml) — the foundation. Dispatch hub tentacle. ~3-5 days.
2. **vault#339** (vault Dockerfile + non-loopback auth) — can run in parallel after hub#258 starts.
3. **hub#259** (first-boot wizard) — substantial; can start after #258 lands.
4. **parachute.computer#42** (/deploy page) — last in the sequence; depends on the deploy template existing.
5. **hub#260** (module management UI) — biggest, but doesn't gate the closed-beta. Phase 2 work.

## Phase 1 milestone definition

"A friend forks the deploy repo, clicks Deploy to Render, gets a working Parachute install at their own domain in under 5 minutes" — closed-beta-ready bar. Needs:
- hub#258 ✓
- vault#339 ✓
- hub#259 ✓
- parachute.computer#42 ✓

(hub#260 is Phase 2 — gated by Phase 1 but not blocking.)

Dialogue ongoing as the work moves.
