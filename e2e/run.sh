#!/usr/bin/env bash
#
# Run the containerised end-to-end harness and produce a video.
#
#   ./run.sh                                   # against parachute-vault's main
#   ./run.sh --vault-context <path-to-worktree> # against a branch
#   ./run.sh --tag before --vault-context ../parachute-vault
#
# Nothing here touches the host's Parachute: no ~/.parachute, no host tokens,
# no live ports. The stack builds scratch images, runs, and is torn down with
# its volumes.
set -euo pipefail

cd "$(dirname "$0")"
E2E_DIR="$PWD"

VAULT_CONTEXT="../parachute-vault"
APP_CONTEXT="../parachute-app"
TAG="run"
KEEP_UP=0

while [ $# -gt 0 ]; do
  case "$1" in
    --vault-context) VAULT_CONTEXT="$2"; shift 2 ;;
    --app-context)   APP_CONTEXT="$2";   shift 2 ;;
    --tag)           TAG="$2";           shift 2 ;;
    --keep-up)       KEEP_UP=1;          shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

VAULT_CONTEXT="$(cd "$VAULT_CONTEXT" && pwd)"
APP_CONTEXT="$(cd "$APP_CONTEXT" && pwd)"

# Refuse to run against the host's live Parachute home. The whole point of
# this harness is that it can't disturb the machine we develop on, and a
# stray bind mount would be silent.
if [ -n "${PARACHUTE_HOME:-}" ] && [ "${PARACHUTE_HOME}" = "$HOME/.parachute" ]; then
  echo "refusing to run with PARACHUTE_HOME pointed at the live install" >&2
  exit 1
fi

VAULT_IMAGE="parachute-vault:e2e-${TAG}"
APP_IMAGE="parachute-app:e2e-${TAG}"

echo "==> building vault image from ${VAULT_CONTEXT}"
docker build -q -f "${E2E_DIR}/stack/Dockerfile.vault-e2e" -t "${VAULT_IMAGE}" "${VAULT_CONTEXT}" >/dev/null

echo "==> building app image from ${APP_CONTEXT}"
docker build -q -f "${E2E_DIR}/stack/Dockerfile.app-e2e" -t "${APP_IMAGE}" "${APP_CONTEXT}" >/dev/null

export E2E_VAULT_IMAGE="${VAULT_IMAGE}"
export E2E_APP_IMAGE="${APP_IMAGE}"

cleanup() {
  if [ "$KEEP_UP" -eq 0 ]; then
    docker compose -f "${E2E_DIR}/stack/compose.yml" down -v --remove-orphans >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

echo "==> starting stack"
docker compose -f "${E2E_DIR}/stack/compose.yml" up -d --wait

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
  mcr.microsoft.com/playwright:v1.58.2-noble \
  sh -c 'npm i --no-audit --no-fund --silent >/dev/null 2>&1 && npx playwright test --output=artifacts/'"${TAG}"'/output'
STATUS=$?
set -e

echo "==> videos:"
find "${E2E_DIR}/artifacts" -name '*.webm' -newermt '-10 minutes' 2>/dev/null | sed 's/^/    /' || true

exit $STATUS
