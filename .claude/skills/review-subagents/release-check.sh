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
# Checks (v4 — structural only; the reviewer handles judgment):
#   1. A PR to main with code changes must bump the owning package's version and
#      update that package's CHANGELOG.md when it has one. In a monorepo, the root
#      and every independently released workspace package are checked independently.
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

# Discover tracked package manifests that belong to the root package's declared
# workspaces. `git ls-files` expands the workspace globs without depending on a
# populated node_modules; Bun is already the package runner for these repos.
workspace_manifests=""
has_workspaces=0
if command -v bun >/dev/null 2>&1; then
  while IFS= read -r workspace_pattern; do
    [ -n "$workspace_pattern" ] || continue
    has_workspaces=1
    matches=$(git ls-files "${workspace_pattern%/}/package.json" || true)
    while IFS= read -r manifest; do
      [ -n "$manifest" ] || continue
      # Private workspace entries are implementation partitions of the root
      # package, not independently released units (Cloud's workers are the
      # current example), so their source remains owned by the root.
      if bun -e '
        const pkg = await Bun.file(process.argv[1]).json();
        process.exit(pkg.private === true ? 1 : 0);
      ' "$manifest" 2>/dev/null; then
        workspace_manifests="${workspace_manifests}${workspace_manifests:+
}${manifest}"
      fi
    done <<< "$matches"
  done < <(bun -e '
    const root = await Bun.file("package.json").json();
    const workspaces = Array.isArray(root.workspaces)
      ? root.workspaces
      : (root.workspaces?.packages ?? []);
    for (const workspace of workspaces) console.log(workspace);
  ' 2>/dev/null || true)
elif grep -q '"workspaces"' package.json; then
  echo "WARN: bun is not on PATH — workspace packages cannot be discovered; falling back to the single-package check"
fi

if [ "$has_workspaces" -eq 1 ]; then
  # Keep feature-PR output identical to the single-package path below.
  if [ "$base_branch" != "main" ]; then
    echo "OK: feature PR to $base_branch — version bump and changelog exempt under the bundled cadence"
    echo "release-check: PASS"
    exit 0
  fi

  lock_changed=$(echo "$CHANGED" | grep -cE '^(bun\.lock|bun\.lockb|package-lock\.json)$' || true)
  fail=0
  checked_units=0

  is_non_code_path() {
    # Package-local test compiler configuration does not ship with the package.
    # Surface's release branch legitimately carries this residue for an unchanged
    # package while releasing a different workspace package.
    echo "$1" | grep -qE '\.(md|txt)$|^docs/|^\.github/|^LICENSE|^\.gitignore$|^\.claude/|^tsconfig\.test\.json$'
  }

  path_is_in_workspace() {
    local path=$1
    local manifest workspace_dir
    while IFS= read -r manifest; do
      [ -n "$manifest" ] || continue
      workspace_dir=${manifest%/package.json}
      case "$path" in
        "$workspace_dir"/*) return 0 ;;
      esac
    done <<< "$workspace_manifests"
    return 1
  }

  check_unit() {
    local manifest=$1
    local unit_dir=${manifest%/package.json}
    local label=$unit_dir
    local manifest_changed changelog_path changelog_changed changelog_exists
    local version_line_touched old_v new_v version_bumped code_changed rel path

    [ "$manifest" = "package.json" ] && { unit_dir=""; label="root"; }
    grep -q '"version"' "$manifest" 2>/dev/null || return 0

    manifest_changed=$(echo "$CHANGED" | grep -cxF "$manifest" || true)
    changelog_path=${unit_dir:+$unit_dir/}CHANGELOG.md
    changelog_changed=$(echo "$CHANGED" | grep -cxF "$changelog_path" || true)
    changelog_exists=0
    { [ -f "$changelog_path" ] || git cat-file -e "$BASE:$changelog_path" 2>/dev/null; } && changelog_exists=1

    code_changed=""
    while IFS= read -r path; do
      [ -n "$path" ] || continue
      if [ -n "$unit_dir" ]; then
        case "$path" in
          "$unit_dir"/*) rel=${path#"$unit_dir"/} ;;
          *) continue ;;
        esac
      else
        path_is_in_workspace "$path" && continue
        case "$path" in bun.lock|bun.lockb|package-lock.json) continue ;; esac
        rel=$path
      fi
      is_non_code_path "$rel" && continue
      code_changed="${code_changed}${code_changed:+
}${path}"
    done <<< "$CHANGED"

    version_line_touched=0
    old_v=""
    new_v=""
    if [ "$manifest_changed" -gt 0 ] && git diff -U0 "$BASE"...HEAD -- "$manifest" | grep -E '^[+-]' | grep -q '"version"'; then
      version_line_touched=1
      old_v=$(git show "$BASE:$manifest" | grep -m1 '"version"' | cut -d'"' -f4)
      new_v=$(grep -m1 '"version"' "$manifest" | cut -d'"' -f4)
    fi
    version_bumped=0
    [ "$version_line_touched" -eq 1 ] && [ "$old_v" != "$new_v" ] && version_bumped=1

    # An unchanged workspace manifest still owns its source. If that source
    # changed, the normal hard-failure branch below requires a package bump.
    if [ -z "$code_changed" ] && [ "$version_line_touched" -eq 0 ] && [ "$changelog_changed" -eq 0 ]; then
      return 0
    fi
    checked_units=$((checked_units + 1))

    if [ "$version_bumped" -eq 0 ]; then
      echo "FAIL: release-shaped changes in $label but $manifest version did not"
      [ -n "$code_changed" ] && echo "      changed: $(echo "$code_changed" | head -5 | tr '\n' ' ')..."
      fail=1
    elif [ "$changelog_exists" -eq 1 ] && [ "$changelog_changed" -eq 0 ]; then
      echo "FAIL: $label version bumped ($old_v -> $new_v) without a $changelog_path entry (governance rule 2 — the release PR bumps the version AND writes the package changelog covering everything merged since)"
      fail=1
    elif [ "$changelog_exists" -eq 1 ]; then
      echo "OK: release package $label — version bumped $old_v -> $new_v with a changelog entry"
    else
      # Changelog-less packages (currently Cloud's root deploy package) cannot
      # satisfy the paired-file policy; their real version bump remains required.
      echo "OK: release package $label — version bumped $old_v -> $new_v (no package changelog exists)"
    fi

    # The one lockfile is rooted at the monorepo, even for a nested package.
    if [ "$manifest_changed" -gt 0 ] && [ "$lock_changed" -eq 0 ]; then
      if git check-ignore -q bun.lock bun.lockb package-lock.json 2>/dev/null; then
        echo "OK: root lockfile gitignored in this repo"
      elif git diff "$BASE"...HEAD -- "$manifest" | grep -qE '"(dependencies|devDependencies|peerDependencies)"|"[^"]+": *"[~^]?[0-9]' ; then
        echo "WARN: $manifest changed without a root lockfile change — verify deps untouched (version-only bumps may not need it; bun may still rewrite the lock)"
      else
        echo "OK: $manifest change doesn't look dep-shaped"
      fi
    fi

    if [ "$version_line_touched" -eq 1 ] && [ "$version_bumped" -eq 0 ]; then
      echo "FAIL: $manifest version line touched but the value is unchanged ($new_v) despite a bump-shaped diff"
      fail=1
    fi
  }

  check_unit package.json
  while IFS= read -r manifest; do
    [ -n "$manifest" ] && check_unit "$manifest"
  done <<< "$workspace_manifests"

  [ "$checked_units" -eq 0 ] && echo "OK: no release-unit code changes to check"
  if [ "$fail" -eq 0 ]; then
    echo "release-check: PASS"
  else
    echo "release-check: FAIL"
    exit 1
  fi
  exit 0
fi

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

if [ "$fail" -eq 0 ]; then
  echo "release-check: PASS"
else
  echo "release-check: FAIL"
  exit 1
fi
