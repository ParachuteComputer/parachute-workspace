# Governance

Settled 2026-04-25; contracts-check wording updated 2026-07-03 (`Decisions/2026-07-03-patterns-archive`).

## The three rules

1. **No auto-merge.** Agents open PRs with a mandatory independent reviewer pass; the human (Aaron) clicks merge — except where merge authority is explicitly delegated (currently only `parachute-brain`). All core repos have branch protection on `main` (PR-required, no force-push, no deletion). Required-review-count is 0 while solo-team; bumps to ≥1 when a second human contributor joins. A branch-protection "bypass" warning is not authorization.
2. **Version bumps live in release PRs, not feature PRs.** Feature PRs carry code + tests and **do not touch `package.json` version or `CHANGELOG.md`**. A separate release PR bumps the version and writes the changelog covering everything merged since — merging it publishes (see below). Pre-1.0 that bump is the `rc.N` suffix only, keeping `0.X.Y` fixed across the chain; when Aaron says ready-for-release, drop the `-rc` suffix at the same `0.X.Y` to publish `@latest`. Sync the lockfile with every version bump (frozen-lockfile is CI-only). Know the repo's convention — parachute-surface ships stable patch bumps, not rc.

   **Why this changed (2026-07-29).** Every PR used to bump the version and prepend to the changelog, so with N PRs open against one repo, each merge conflicted the other N−1 — on the same two lines, every time. One session burned six rebases on nothing but version numbers and changelog headers. Worse, resolving those conflicts silently *dropped* two merged changelog entries, because a `str.replace` anchored on a header that didn't exist is a no-op that fails nothing. Shared-line edits in every PR is the whole cause; removing them removes the class.

   **Publishing is on merge, not on a remembered tag.** CI compares `package.json`'s version against npm and publishes when it's new — idempotent, refuses on an ambiguous registry, and refuses to move a dist-tag backwards. So the release PR *is* the release signal, and there is no tag to forget. (Tag pushes still work and still override, for re-releases.) A dist-tag is derived from the version being published, never from the git ref — deriving it from `GITHUB_REF_NAME` sends every merge-triggered publish to `@latest`, which is how an rc briefly became `@latest`.

   **Stack related PRs** rather than opening them all against `main`: branch each off the previous one. Independent work can go parallel safely now that feature PRs share no lines.
3. **Contracts check in every review.** Each PR review surfaces which cross-repo contracts the change touches (wire shapes, OAuth issuer behavior, portable-md format, module protocol) and whether it conforms. Contract docs live with the repo that enforces them (migrating there as parachute-patterns archives); the specialist briefs in `.claude/skills/review-subagents/` encode the load-bearing ones.

## PR flow

- **Concurrent when disjoint, bundled within**: concurrent PRs per repo are fine when they don't collide (see `orchestration.md` for the test); one PR per coherent session of work (multiple commits fine). Side-discoveries → `gh issue create` rather than widening the PR.
- **Reviewer nits relevant to the diff fold inline** (same PR, same rc); out-of-scope findings become issues.
- **Verified-conditional merge**: after `gh pr merge`, confirm `state == MERGED` before any hygiene (reset/force-push of the dev branch) — transient merge failures + unconditional hygiene have clobbered open PRs before.
- **Never merge on a red/UNSTABLE gate without reading it.** Don't assume a red gate is pre-existing.
- **External PRs** require Aaron's identity-verified approval — never merge outside-contributor code on code-scope alone.

## npm publishes

CI's job, gated by `v*` tag push (OIDC trusted publishing — no tokens). The tag push IS the release signal. After publishing, verify: `npm view <pkg>@<version> dist.tarball`. Watch for bun's stale-manifest cache on deploy boxes (`rm -rf ~/.bun/install/cache` if a fresh version won't resolve).

## Architectural shifts → migration files

When a PR decides an architectural shift — canonical install path, a doc statement quoted across the workspace, a repo's role — ship a migration checklist file in the same PR listing every code/doc location that needs updating, and track which PRs landed each item. (Historically these lived in `parachute-patterns/migrations/`; as that repo archives, new ones land in the destination decided by the coherence program — check `Work/repo-coherence-program` in the team vault.) Run an audit for stale canonical references after shifts and before releases.
