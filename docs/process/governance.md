# Governance

Settled 2026-04-25; contracts-check wording updated 2026-07-03 (`Decisions/2026-07-03-patterns-archive`).

## The three rules

1. **No auto-merge.** Agents open PRs with a mandatory independent reviewer pass; the human (Aaron) clicks merge — except where merge authority is explicitly delegated (currently only `parachute-brain`). All core repos have branch protection on `main` (PR-required, no force-push, no deletion). Required-review-count is 0 while solo-team; bumps to ≥1 when a second human contributor joins. A branch-protection "bypass" warning is not authorization.
2. **RC versioning before `@latest`.** Pre-1.0, every code-touching PR bumps the `rc.N` suffix only — keep `0.X.Y` fixed across the chain. **Push the matching `v0.X.Y-rc.N` tag on merge** — the tag triggers CI to publish `@rc` (verify with `npm view <pkg> dist-tags`). When Aaron says ready-for-release: drop the `-rc` suffix, same `0.X.Y`, publish `@latest`. Doc-only PRs skip rc. Sync the lockfile with every version bump (frozen-lockfile is CI-only). Know the repo's convention — parachute-surface ships stable patch bumps, not rc.
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
