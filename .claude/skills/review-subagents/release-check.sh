#!/usr/bin/env bash
#
# release-check.sh — structural release hygiene for a PR branch, vs its base.
# Run from the REPO ROOT of the module repo (not the workspace). Exits non-zero
# on a hard failure; prints WARNs for judgment calls the reviewer should eyeball.
#
#   cd parachute-vault && ../.claude/skills/review-subagents/release-check.sh
#
# Bundled-release cadence (governance rule 2): feature PRs land on `next` and never
# touch package.json's version or CHANGELOG.md; the batch release PR (the `next -> main`
# PR, governance rule 1) bumps the version once and writes the changelog covering
# everything merged since. So version and changelog must move TOGETHER, never alone.
#
# Pass the PR base branch as $1 when it is known. Otherwise the script asks
# GitHub for the current PR's baseRefName and falls back to main outside a PR.
#
# Checks (v3 — structural only; the reviewer handles judgment):
#   1. A PR to main with code changes must bump the version and update CHANGELOG.md.
#      Feature PRs to next are exempt: release discipline lives in next -> main.
#   2. If package.json changed, the lockfile must have changed with it (frozen-lockfile is
#      CI-only; a version/dep bump without a lockfile sync breaks CI). Repos with gitignored
#      lockfiles pass automatically.
#   3. The package.json version line can be touched without the value actually changing
#      (e.g. a no-op reformat) — that's a FAIL on an otherwise bump-shaped diff, not a free
#      pass. (Ordering regressions — rc.3 -> rc.2 — stay the reviewer's eyeball.)
set -euo pipefail

# Module repos only — the workspace and docs-only repos have nothing to version-check.
[ -f package.json ] || { echo "OK: no package.json here — not a module repo, nothing to check"; exit 0; }

if [ "$#" -gt 1 ]; then
  echo "Usage: release-check.sh [base-branch]" >&2
  exit 2
fi

base_branch=${1:-}
if [ -z "$base_branch" ] && command -v gh >/dev/null 2>&1; then
  base_branch=$(gh pr view --json baseRefName --jq .baseRefName 2>/dev/null || true)
fi
base_branch=${base_branch:-main}
base_branch=${base_branch#origin/}
BASE="origin/$base_branch"

git fetch origin "$base_branch" --quiet 2>/dev/null || true
CHANGED=$(git diff --name-only "$BASE"...HEAD)
[ -z "$CHANGED" ] && { echo "OK: no changes vs $BASE"; exit 0; }

code_changed=$(echo "$CHANGED" | grep -vE '\.(md|txt)$|^docs/|^\.github/|^LICENSE|^\.gitignore$|^\.claude/' || true)
pkg_changed=$(echo "$CHANGED" | grep -cx 'package.json' || true)
lock_changed=$(echo "$CHANGED" | grep -cE '^(bun\.lock|bun\.lockb|package-lock\.json)$' || true)
changelog_changed=$(echo "$CHANGED" | grep -cx 'CHANGELOG.md' || true)

version_line_touched=0
old_v=""
new_v=""
if [ "$pkg_changed" -gt 0 ] && git diff -U0 "$BASE"...HEAD -- package.json | grep -E '^[+-]' | grep -q '"version"'; then
  version_line_touched=1
  old_v=$(git show "$BASE:package.json" | grep -m1 '"version"' | cut -d'"' -f4)
  new_v=$(grep -m1 '"version"' package.json | cut -d'"' -f4)
fi
version_bumped=0
[ "$version_line_touched" -eq 1 ] && [ "$old_v" != "$new_v" ] && version_bumped=1

fail=0

# 1. only a PR to main is release-shaped. Feature PRs to next deliberately
# leave version + changelog discipline to the later next -> main release PR.
if [ "$base_branch" != "main" ]; then
  echo "OK: feature PR to $base_branch — version bump and changelog exempt under the bundled cadence"
elif [ -z "$code_changed" ] && [ "$changelog_changed" -eq 0 ]; then
  echo "OK: doc-only PR to main — version bump exempt"
elif [ "$version_bumped" -eq 0 ]; then
  echo "FAIL: release-shaped changes in a PR to main but package.json version did not"
  [ -n "$code_changed" ] && echo "      changed: $(echo "$code_changed" | head -5 | tr '\n' ' ')..."
  fail=1
elif [ "$changelog_changed" -eq 0 ]; then
  echo "FAIL: version bumped ($old_v -> $new_v) without a CHANGELOG.md entry (governance rule 2 — the release PR bumps the version AND writes the changelog covering everything merged since)"
  fail=1
else
  echo "OK: release PR to main — version bumped $old_v -> $new_v with a changelog entry"
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

# 3. version line touched but value unchanged — a no-op on a bump-shaped diff
if [ "$base_branch" = "main" ] && [ "$version_line_touched" -eq 1 ] && [ "$version_bumped" -eq 0 ]; then
  echo "FAIL: package.json version line touched but the value is unchanged ($new_v) despite a bump-shaped diff"
  fail=1
fi

[ "$fail" -eq 0 ] && echo "release-check: PASS" || { echo "release-check: FAIL"; exit 1; }
