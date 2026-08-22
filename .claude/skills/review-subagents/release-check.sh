#!/usr/bin/env bash
#
# release-check.sh — structural release hygiene for a PR branch, vs origin/main.
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
# Checks (v2 — structural only; the reviewer handles judgment):
#   1. Version and changelog move together: a version bump without a CHANGELOG.md entry,
#      or a changelog touch without a version bump, both FAIL. Neither touched — the
#      normal feature PR under the bundled cadence — is a pass.
#   2. If package.json changed, the lockfile must have changed with it (frozen-lockfile is
#      CI-only; a version/dep bump without a lockfile sync breaks CI). Repos with gitignored
#      lockfiles pass automatically.
#   3. The package.json version line can be touched without the value actually changing
#      (e.g. a no-op reformat) — that's a FAIL on an otherwise bump-shaped diff, not a free
#      pass. (Ordering regressions — rc.3 -> rc.2 — stay the reviewer's eyeball.)
set -euo pipefail

# Module repos only — the workspace and docs-only repos have nothing to version-check.
[ -f package.json ] || { echo "OK: no package.json here — not a module repo, nothing to check"; exit 0; }

git fetch origin main --quiet 2>/dev/null || true
BASE="origin/main"
CHANGED=$(git diff --name-only "$BASE"...HEAD)
[ -z "$CHANGED" ] && { echo "OK: no changes vs $BASE"; exit 0; }

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

# 1. version + changelog move together (bundled-release cadence, governance rule 2)
if [ "$version_bumped" -eq 1 ] && [ "$changelog_changed" -eq 0 ]; then
  echo "FAIL: version bumped ($old_v -> $new_v) without a CHANGELOG.md entry (governance rule 2 — the release PR bumps the version AND writes the changelog covering everything merged since)"
  fail=1
elif [ "$version_bumped" -eq 0 ] && [ "$changelog_changed" -gt 0 ]; then
  echo "FAIL: CHANGELOG.md touched without a version bump (governance rule 2 — feature PRs don't touch CHANGELOG.md; only the batch release PR does, alongside the bump)"
  fail=1
elif [ "$version_bumped" -eq 1 ] && [ "$changelog_changed" -gt 0 ]; then
  echo "OK: release PR — version bumped $old_v -> $new_v with a changelog entry"
elif [ "$version_line_touched" -eq 1 ]; then
  echo "OK: feature PR — no net version change (see check 3)"
else
  echo "OK: feature PR — no version bump, no changelog touch (exempt under the bundled cadence)"
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
if [ "$version_line_touched" -eq 1 ] && [ "$version_bumped" -eq 0 ]; then
  echo "FAIL: package.json version line touched but the value is unchanged ($new_v) despite a bump-shaped diff"
  fail=1
fi

[ "$fail" -eq 0 ] && echo "release-check: PASS" || { echo "release-check: FAIL"; exit 1; }
