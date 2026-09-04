# e2e — the video harness

A self-contained browser stack that proves a change works *as a person
experiences it*, and records a video doing it. The video is the deliverable,
not a debugging aid: the working agreement is that a PR arrives with one.

```
./run.sh --vault-context ../../.worktrees/my-branch --tag after
./run.sh --spec specs/nostr-key-door.spec.ts
```

Name a spec with `--spec`. The specs are not interchangeable: `walkthrough.spec.ts`
reads `narrate/tour_timing.json`, a gitignored build artifact of `narrate/`, so a
bare run in a fresh checkout fails there for reasons that have nothing to do with
the product.

## The one hard rule

**Nothing here may touch the host's Parachute.** No `~/.parachute`, no host
tokens, no live ports (1939/1940/1944 are deliberately avoided). Vaults are
scratch: created on container boot, destroyed with the stack. `run.sh` refuses
to start if `PARACHUTE_HOME` points at the live install.

## Why it needs its own images

`parachute-vault/Dockerfile` is the deployment artifact and is Alpine (musl).
whisper.cpp ships its Linux CLIs as glibc Ubuntu binaries, which cannot execute
under musl — so a run that needs *real* transcription needs a glibc base.
`stack/Dockerfile.vault-e2e` is that, plus ffmpeg, the CLI, and a small model.
Keeping it separate means the harness can carry a 74 MB model without putting
it in the image people deploy.

## Shape

- **One origin.** Caddy serves the app and reverse-proxies `/vault/*` to the
  vault, so the browser sees a single-origin install — the shape self-hosted
  Parachute ships, and one with no CORS in the way.
- **A hub, for the one spec that is about a hub.** `specs/nostr-key-door.spec.ts`
  needs a real hub process — a browser, a cookie jar, and an HTTP `Set-Cookie`
  are the whole subject — so `stack/compose.yml` runs one, built by `run.sh`
  from a **parachute-hub checkout** using that repo's own `Dockerfile`. It has
  to be a checkout: the door (`/api/auth/nostr/*`, the NIP-07 button,
  `parachute auth link-pubkey`, `PARACHUTE_NOSTR_LOGIN_2FA`) lands on hub
  `next` and is in no published npm release, so `--hub-context` is how you say
  which ref. The ref is printed at build time.
- **The hub is its own origin, not behind the Caddy.** `http://hub:1939`. Two
  reasons: the hub's paths (`/login`, `/admin`, `/api`, `/oauth`) would collide
  with the app's SPA routes at a shared origin, and the key door binds the
  signed event to an origin the hub itself answers on.
- **Every other spec still skips the hub.** The vault's `VAULT_AUTH_TOKEN` is a
  server-wide bearer, so those specs seed the app's connected-vault state
  directly rather than driving OAuth. `nostr-key-door.spec.ts` seeds it too,
  for its second half, and says so in its header — the hub in this stack does
  not issue for this vault, and cannot: the hub proxies only modules it
  supervises on `127.0.0.1`, and `services.json` has no host field at all.
- **Real media.** Chromium is given a WAV via `--use-fake-device-for-media-stream`
  and `--use-file-for-fake-audio-capture`, so `getUserMedia` and `MediaRecorder`
  run for real. Nothing in the product is stubbed.

## Evidence discipline

**A green run on its own is not evidence.** Run the same spec against an image
built from the unfixed baseline and confirm it fails *for the stated reason* —
then you know the spec can see the bug at all. `--tag before` / `--tag after`
keep the two artifact sets apart.

## Gotchas that cost real time

- **Don't flatten the whisper `.so` files** into `/usr/local/lib`. ggml
  discovers its compute backends by scanning the directory its own library
  lives in, and `install` dereferences the versioned symlink chain. Both break
  it, and the failure is `GGML_ASSERT(device) failed` deep in
  `ggml_backend_dev_init`. Keep the tarball layout; point `LD_LIBRARY_PATH`
  at it.
- **`getUserMedia` requires a secure context.** `http://app:8080` is neither
  HTTPS nor localhost, so Chromium hides `navigator.mediaDevices` and the app
  reports "Microphone is not available in this browser" — which looks exactly
  like a product bug. `--unsafely-treat-insecure-origin-as-secure` did not work;
  making the origin literally `localhost` and adding
  `--host-resolver-rules=MAP localhost app` does. The secure-context decision
  is made on the hostname, not the resolved address.
- **colima only mounts `$HOME`.** A bind mount from `/tmp` silently isn't there.
- **`PARACHUTE_HUB_ORIGIN` is not optional for the key door.** The origin set
  the door will accept a signed `u` tag against (`linkageBoundOrigins`)
  deliberately DROPS a Host-derived issuer, so an unconfigured hub reached at
  `http://hub:1939` accepts only the loopback aliases and refuses every event
  as `invalid_event` — a rejection that reads like a signing bug three steps
  from its cause. Setting the env var makes the issuer env-sourced and trusted.
- **The expired-nonce case really does take five minutes.** The hub's challenge
  TTL is a module constant with no env seam, and `challenge_expired` versus
  `unknown_challenge` only differ on the far side of it. It is one `test()`,
  and it is the reason `--spec` is worth reaching for.
- **Assert on a settled state.** Checking that an element is *absent* right
  after navigation passes trivially, because nothing has rendered yet. Wait for
  whichever state appears first, then judge.
