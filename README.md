# Parachute Computer — workspace meta-repo

The top-level workspace for the Parachute ecosystem. Each Parachute module is its own git repo under this directory. This repo (`workspace`) tracks **workspace-level orchestration** — the conventions, skills, and agents that span the ecosystem.

> ⚠️ **Read [`CLAUDE.md`](./CLAUDE.md) first.** It documents the committed-core modules, the multi-repo discipline, the architectural-shift workflow, and how Claude agents are dispatched across repos. The CLAUDE.md is canonical; this README is just an entry point.

## What lives here

| Path | Tracked? | Purpose |
|---|---|---|
| [`CLAUDE.md`](./CLAUDE.md) | ✅ | Workspace conventions + module roster + architectural-shift discipline |
| [`.claude/agents/`](./.claude/agents) | ✅ | Custom subagent definitions (e.g. reviewer, tentacle) used across Parachute work |
| [`.claude/commands/`](./.claude/commands) | ✅ | Custom slash commands (e.g. `/handoff`) |
| `.claude/settings.local.json` | 🚫 | Operator-local — per-machine permissions, not tracked |
| `scratch/` | ✅ | Session handoffs, process audits, thinking notes |
| `docs/` | ✅ | Workspace-level documentation (when we accumulate it) |
| `parachute-*/`, `prism/`, `tailshare/`, etc. | 🚫 | **Sibling repos** — each has its own `.git/` and remote. Cloned at this level by convention. |
| Workspace-root `*.md` drafts | 🚫 | Historical artifacts (`DESIGN-*`, `BETA-EMAIL-*`, `RELEASE-NOTES-*`, `WAKE-UP-*`, etc.). Move to `docs/historical/` to track. |

## Cloning this on a fresh machine

```bash
# 1. Clone the workspace meta-repo
git clone <this-repo-url> ~/ParachuteComputer
cd ~/ParachuteComputer

# 2. Clone each Parachute module you need
gh repo clone ParachuteComputer/parachute-hub
gh repo clone ParachuteComputer/parachute-vault
gh repo clone ParachuteComputer/parachute-surface
gh repo clone ParachuteComputer/parachute-scribe
gh repo clone ParachuteComputer/parachute-notes   # archiving — notes-ui moved into parachute-surface; clone only for history
gh repo clone ParachuteComputer/parachute-patterns
gh repo clone ParachuteComputer/parachute.computer
gh repo clone ParachuteComputer/parachute-runner

# 3. (Optional) Clone explorations
gh repo clone ParachuteComputer/parachute-agent
# ... others as needed
```

The committed-core line is documented in `CLAUDE.md`. As of 2026-05-27: **vault, surface, scribe, hub** are the four committed-core modules (surface renamed from app 2026-05-27).

## Workspace-level patterns + audit tooling

- **Migration discipline**: when making an architectural shift, ship a `parachute-patterns/migrations/YYYY-MM-DD-<slug>.md` file. See `CLAUDE.md` § "When making architectural shifts."
- **Audit script**: `parachute-patterns/scripts/audit-canonical-refs.sh` greps for stale architecture references (run after shifts or before releases).

## Customizing your environment

Operator-local Claude Code settings go in `.claude/settings.local.json` (gitignored). The tracked `.claude/` files (agents, commands) are workspace defaults — extend them in your local fork if you want personal customizations.

## License

The workspace meta-repo itself has no license — it's an orchestration container. Each Parachute module has its own LICENSE (currently AGPL-3.0 for the committed-core modules).
