#!/usr/bin/env bash
#
# release-check.sh — structural release hygiene for a PR branch, vs origin/main.
# Run from the REPO ROOT of the module repo (not the workspace). Exits non-zero
# on a hard failure; prints WARNs for judgment calls the reviewer should eyeball.
#
#   cd parachute-vault && ../.claude/skills/review-subagents/release-check.sh
#
# Checks (v1 — structural only; the reviewer handles judgment):
#   1. If code files changed vs origin/main, package.json "version" must have changed too
#      (rc bump per governance rule 2). Doc-only diffs are exempt.
#   2. If package.json changed, the lockfile must have changed with it (frozen-lockfile is
#      CI-only; a version/dep bump without a lockfile sync breaks CI). Repos with gitignored
#      lockfiles pass automatically.
#   3. Version must not be UNCHANGED when a bump-shaped diff touched package.json.
#      (Ordering regressions — rc.3 → rc.2 — are the reviewer's eyeball, not this script's.)
set -euo pipefail

# Module repos only — the workspace and docs-only repos have nothing to version-check.
[ -f package.json ] || { echo "OK: no package.json here — not a module repo, nothing to check"; exit 0; }

git fetch origin main --quiet 2>/dev/null || true
BASE="origin/main"
CHANGED=$(git diff --name-only "$BASE"...HEAD)
[ -z "$CHANGED" ] && { echo "OK: no changes vs $BASE"; exit 0; }

code_changed=$(echo "$CHANGED" | grep -vE '\.(md|txt)$|^docs/|^\.github/|^LICENSE|^\.gitignore$|^\.claude/' || true)
pkg_changed=$(echo "$CHANGED" | grep -cx 'package.json' || true)
lock_changed=$(echo "$CHANGED" | grep -cE '^(bun\.lock|bun\.lockb|package-lock\.json)$' || true)

fail=0

# 1. code => version bump
if [ -n "$code_changed" ]; then
  if git diff "$BASE"...HEAD -- package.json | grep -q '"version"'; then
    old_v=$(git show "$BASE:package.json" | grep -m1 '"version"' | cut -d'"' -f4)
    new_v=$(grep -m1 '"version"' package.json | cut -d'"' -f4)
    echo "OK: version bumped $old_v -> $new_v"
    # 3. forward-only (string compare is enough to catch identical; ordering left to the reviewer)
    [ "$old_v" = "$new_v" ] && { echo "FAIL: version unchanged ($new_v) despite a bump-shaped diff"; fail=1; }
  else
    echo "FAIL: code files changed but package.json version did not (governance rule 2 — rc bump per code PR)"
    echo "      changed: $(echo "$code_changed" | head -5 | tr '\n' ' ')..."
    fail=1
  fi
else
  echo "OK: doc-only diff — rc bump exempt"
fi

# 2. package.json => lockfile
if [ "$pkg_changed" -gt 0 ] && [ "$lock_changed" -eq 0 ]; then
  if git check-ignore -q bun.lock bun.lockb package-lock.json 2>/dev/null; then
    echo "OK: lockfile gitignored in this repo"
  elif git diff "$BASE"...HEAD -- package.json | grep -qE '"(dependencies|devDependencies|peerDependencies)"|"[^"]+": *"[~^]?[0-9]' ; then
    echo "WARN: package.json changed without a lockfile change — verify deps untouched (version-only bumps may not need it; bun may still rewrite the lock)"
  else
    echo "OK: package.json change doesn't look dep-shaped"
  fi
fi

[ "$fail" -eq 0 ] && echo "release-check: PASS" || { echo "release-check: FAIL"; exit 1; }
