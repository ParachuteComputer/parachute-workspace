# Workspace docs — index

- [process/governance.md](process/governance.md) — the three rules (no auto-merge · version-bumps-in-release-PRs · contracts check), PR flow, external PRs, publish-on-merge, the migration-file discipline
- [process/orchestration.md](process/orchestration.md) — the dispatch model: orchestrator vs builders, briefing, verifying agent outputs, the reviewer gate, session boundaries
- [process/development.md](process/development.md) — the dev ritual in full (Orient/Claim/Log/Release), the GitHub-issues boundary, working without vault access
- [process/context.md](process/context.md) — context-engineering conventions: gotchas-only CLAUDE.md, skills for process, one home per instruction
- [historical/](historical/) — **local-only** bin for pre-vault-era root artifacts (untracked by design — public repo, private session files; see its README). The vault's `Decisions/` + `Strategy/` are where that content belongs.
- [../.claude/skills/review-subagents/SKILL.md](../.claude/skills/review-subagents/SKILL.md) — the review roster: generalist reviewer (every PR) + domain specialists (wire-contract congruence, auth-and-scope) + the release-check script
- [../.claude/skills/verify/SKILL.md](../.claude/skills/verify/SKILL.md) — the verification discipline: before-PR end-to-end checks, verifying agent claims, live verification, test integrity, environment-safety hard rules
