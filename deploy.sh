#!/usr/bin/env bash
# Triggers an Ownship deployment and (optionally) waits for it to go live.
# Auth is header-only; the token is never echoed or written to disk.
set -euo pipefail

: "${OWNSHIP_TOKEN:?missing token input}"
: "${OWNSHIP_PROJECT_ID:?missing project-id input}"
OWNSHIP_API_URL="${OWNSHIP_API_URL:-https://api.ownship.dev}"
OWNSHIP_API_URL="${OWNSHIP_API_URL%/}"
OWNSHIP_WAIT="${OWNSHIP_WAIT:-true}"

# Sets HTTP_CODE and BODY; HTTP_CODE is 000 when the request never got an answer.
api() {
  local method="$1" path="$2" out
  out="$(curl -sS -X "$method" "${OWNSHIP_API_URL}${path}" \
    -H "Authorization: Bearer ${OWNSHIP_TOKEN}" \
    -H 'Content-Type: application/json' \
    --max-time 30 -w '\n%{http_code}' 2>&1)" || true
  HTTP_CODE="${out##*$'\n'}"
  BODY="${out%$'\n'*}"
}

json_field() {
  python3 -c '
import json, sys
try:
    v = json.load(sys.stdin).get(sys.argv[1])
except Exception:
    v = None
if isinstance(v, list):
    v = "; ".join(map(str, v))
print("" if v is None else v)
' "$1"
}

# The API answers {error, message}; fall back to the raw body when it isn't JSON.
describe_error() {
  local msg
  msg="$(json_field message <<<"$BODY")"
  echo "HTTP ${HTTP_CODE}: ${msg:-$BODY}"
}

echo "Triggering deployment for project ${OWNSHIP_PROJECT_ID}…"
api POST "/projects/${OWNSHIP_PROJECT_ID}/deploy"
if [[ "$HTTP_CODE" != 2* ]]; then
  echo "::error::deploy request failed ($(describe_error))" >&2
  exit 1
fi
deployment_id="$(json_field id <<<"$BODY")"
if [[ -z "$deployment_id" ]]; then
  echo "::error::deploy request did not return a deployment id" >&2
  exit 1
fi
echo "deployment-id=${deployment_id}" >>"$GITHUB_OUTPUT"
echo "Created deployment ${deployment_id}"

if [[ "$OWNSHIP_WAIT" != "true" ]]; then
  exit 0
fi

# ~20 min budget; transient network or 5xx errors are retried a few times in a row.
status='queued'
failures=0
for _ in $(seq 1 240); do
  sleep 5
  api GET "/deployments/${deployment_id}"
  if [[ "$HTTP_CODE" == 000 || "$HTTP_CODE" == 5* || "$HTTP_CODE" == 429 ]]; then
    failures=$((failures + 1))
    if ((failures >= 6)); then
      echo "::error::could not read deployment ${deployment_id} ($(describe_error))" >&2
      exit 1
    fi
    echo "::warning::status check failed ($(describe_error)), retrying"
    continue
  fi
  if [[ "$HTTP_CODE" != 2* ]]; then
    echo "::error::could not read deployment ${deployment_id} ($(describe_error))" >&2
    exit 1
  fi
  failures=0
  status="$(json_field status <<<"$BODY")"
  case "$status" in
    live)
      url="$(json_field url <<<"$BODY")"
      echo "url=${url}" >>"$GITHUB_OUTPUT"
      echo "Deployment is live${url:+ at ${url}}"
      exit 0
      ;;
    failed | superseded | rolledback | lost)
      error="$(json_field error <<<"$BODY")"
      echo "::error::deployment ${deployment_id} ended as '${status}'${error:+: ${error}}" >&2
      exit 1
      ;;
    *)
      echo "  status: ${status}"
      ;;
  esac
done

echo "::error::timed out waiting for deployment ${deployment_id} (last status: ${status})" >&2
exit 1
