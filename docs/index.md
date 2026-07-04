# Workspace docs — index

- [process/governance.md](process/governance.md) — the three rules (no auto-merge · RC versioning · contracts check), PR flow, external PRs, npm-publish-via-tag-CI, the migration-file discipline
- [process/orchestration.md](process/orchestration.md) — the dispatch model: orchestrator vs builders, briefing, verifying agent outputs, the reviewer gate, session boundaries
- [process/development.md](process/development.md) — the dev ritual in full (Orient/Claim/Log/Release), the GitHub-issues boundary, working without vault access
- [historical/](historical/) — **local-only** bin for pre-vault-era root artifacts (untracked by design — public repo, private session files; see its README). The vault's `Decisions/` + `Strategy/` are where that content belongs.
- [../.claude/skills/review-subagents/SKILL.md](../.claude/skills/review-subagents/SKILL.md) — the review roster: generalist reviewer (every PR) + domain specialists (wire-contract congruence, auth-and-scope) + the release-check script
