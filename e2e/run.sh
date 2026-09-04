#!/usr/bin/env bash
#
# Run the containerised end-to-end harness and produce a video.
#
#   ./run.sh                                   # against parachute-vault's main
#   ./run.sh --vault-context <path-to-worktree> # against a branch
#   ./run.sh --tag before --vault-context ../parachute-vault
#   ./run.sh --spec specs/nostr-key-door.spec.ts
#
# `--spec` exists because the specs are not interchangeable: walkthrough.spec.ts
# reads `narrate/tour_timing.json`, which is a build artifact of `narrate/` and
# is gitignored, so a bare run in a fresh checkout fails there for reasons that
# have nothing to do with the product. Name the spec you mean.
#
# Nothing here touches the host's Parachute: no ~/.parachute, no host tokens,
# no live ports. The stack builds scratch images, runs, and is torn down with
# its volumes.
set -euo pipefail

cd "$(dirname "$0")"
E2E_DIR="$PWD"

VAULT_CONTEXT="../parachute-vault"
APP_CONTEXT="../parachute-app"
HUB_CONTEXT="../parachute-hub"
TAG="run"
KEEP_UP=0
SPEC=""

while [ $# -gt 0 ]; do
  case "$1" in
    --vault-context) VAULT_CONTEXT="$2"; shift 2 ;;
    --app-context)   APP_CONTEXT="$2";   shift 2 ;;
    --hub-context)   HUB_CONTEXT="$2";   shift 2 ;;
    --spec)          SPEC="$2";          shift 2 ;;
    --tag)           TAG="$2";           shift 2 ;;
    --keep-up)       KEEP_UP=1;          shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

VAULT_CONTEXT="$(cd "$VAULT_CONTEXT" && pwd)"
APP_CONTEXT="$(cd "$APP_CONTEXT" && pwd)"
HUB_CONTEXT="$(cd "$HUB_CONTEXT" && pwd)"

# Refuse to run against the host's live Parachute home. The whole point of
# this harness is that it can't disturb the machine we develop on, and a
# stray bind mount would be silent.
if [ -n "${PARACHUTE_HOME:-}" ] && [ "${PARACHUTE_HOME}" = "$HOME/.parachute" ]; then
  echo "refusing to run with PARACHUTE_HOME pointed at the live install" >&2
  exit 1
fi

VAULT_IMAGE="parachute-vault:e2e-${TAG}"
APP_IMAGE="parachute-app:e2e-${TAG}"
HUB_IMAGE="parachute-hub:e2e-${TAG}"

# The hub user the key door signs in as, and the keys linked to it. Both are
# read by the spec too (via the env below), so run.sh and the browser cannot
# disagree about which key belongs to whom.
HUB_USER="${E2E_HUB_USER:-keyholder}"
KEYS_FILE="${E2E_DIR}/fixtures/nostr-keys.json"
pubkey_of() { python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))[sys.argv[2]]["pubkey"])' "$KEYS_FILE" "$1"; }

# Which ref each image was built from. Printed, not asserted: the hub features
# under test live on `next` and a run against a context that predates them
# fails in ways that read as product bugs, so the ref belongs in the log.
say_ref() { git -C "$1" describe --always --dirty 2>/dev/null || echo "(not a git checkout)"; }

echo "==> building vault image from ${VAULT_CONTEXT}"
docker build -q -f "${E2E_DIR}/stack/Dockerfile.vault-e2e" -t "${VAULT_IMAGE}" "${VAULT_CONTEXT}" >/dev/null

echo "==> building app image from ${APP_CONTEXT}"
docker build -q -f "${E2E_DIR}/stack/Dockerfile.app-e2e" -t "${APP_IMAGE}" "${APP_CONTEXT}" >/dev/null

# The hub is built from the hub repo's OWN Dockerfile — it is a real deployment
# artifact (unlike the vault's, which is Alpine and can't run whisper.cpp), so
# there is nothing for the harness to add and every reason not to fork it. The
# build is the slow one in this script: `bun install` plus the admin SPA's Vite
# build, a few minutes cold, seconds warm.
echo "==> building hub image from ${HUB_CONTEXT} ($(say_ref "${HUB_CONTEXT}"))"
docker build -q -f "${HUB_CONTEXT}/Dockerfile" -t "${HUB_IMAGE}" "${HUB_CONTEXT}" >/dev/null

export E2E_VAULT_IMAGE="${VAULT_IMAGE}"
export E2E_APP_IMAGE="${APP_IMAGE}"
export E2E_HUB_IMAGE="${HUB_IMAGE}"
export E2E_HUB_USER="${HUB_USER}"

cleanup() {
  if [ "$KEEP_UP" -eq 0 ]; then
    docker compose -f "${E2E_DIR}/stack/compose.yml" down -v --remove-orphans >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

echo "==> starting stack"
docker compose -f "${E2E_DIR}/stack/compose.yml" up -d --wait

# Seed the door. `parachute auth link-pubkey` is the operator-privilege bind the
# design note's §4 dead-end message names, and it writes hub.db directly rather
# than going over HTTP — so it runs INSIDE the hub container, where
# PARACHUTE_HOME already points at the right disk. Two keys onto one user: the
# happy path spends `linked`, and the "unlinked after login" case spends
# `linkedForUnlink` so it can drop its own link without disarming the other
# tests. `neverLinked` is deliberately not seeded — that is its whole job.
echo "==> linking test pubkeys to hub user ${HUB_USER}"
for k in linked linkedForUnlink; do
  docker compose -f "${E2E_DIR}/stack/compose.yml" exec -T hub \
    bun src/cli.ts auth link-pubkey --user "${HUB_USER}" "$(pubkey_of "$k")" \
    | sed 's/^/    /'
done

NETWORK="$(docker compose -f "${E2E_DIR}/stack/compose.yml" ps --format json \
  | python3 -c 'import sys,json;print(next(iter(json.loads(l)["Networks"] for l in sys.stdin if l.strip())))' 2>/dev/null || echo "parachute-e2e_default")"

ARTIFACTS="${E2E_DIR}/artifacts/${TAG}"
rm -rf "${ARTIFACTS}"; mkdir -p "${ARTIFACTS}"

echo "==> running playwright on network ${NETWORK}"
set +e
docker run --rm \
  --network "${NETWORK}" \
  -v "${E2E_DIR}:/e2e" \
  -w /e2e \
  -e E2E_APP_URL="http://app:8080" \
  -e E2E_VAULT_URL="http://app:8080/vault/demo" \
  -e E2E_VAULT_TOKEN="${E2E_VAULT_TOKEN:-e2e-scratch-token-not-a-secret}" \
  -e E2E_AUDIO_FIXTURE="/e2e/fixtures/spoken-phrase.wav" \
  -e E2E_HUB_URL="http://hub:1939" \
  -e E2E_HUB_USER="${HUB_USER}" \
  -e E2E_NOSTR_KEYS="/e2e/fixtures/nostr-keys.json" \
  mcr.microsoft.com/playwright:v1.58.2-noble \
  sh -c 'npm i --no-audit --no-fund --silent >/dev/null 2>&1 && npx playwright test '"${SPEC}"' --output=artifacts/'"${TAG}"'/output'
STATUS=$?
set -e

echo "==> videos:"
find "${E2E_DIR}/artifacts" -name '*.webm' -newermt '-10 minutes' 2>/dev/null | sed 's/^/    /' || true

exit $STATUS
