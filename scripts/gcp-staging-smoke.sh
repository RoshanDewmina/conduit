#!/usr/bin/env bash
# gcp-staging-smoke.sh — black-box production smoke test for the GCP Cloud Run path.
#
# Drives the DEPLOYED staging control plane through its real public HTTP API and
# proves the full cloud pipeline end-to-end with no mocks:
#
#   POST /agents (runtime=gcp_cloud_run)   -> provisions a real Cloud Run Job
#   POST /runs  (command="echo <marker>")  -> dispatchRun mints a runner token and
#                                             launches a real Job Execution
#   ... the container's agent-runner execs the command, streams stdout back to
#       POST /runs/{id}/logs, polls GET /runs/{id}/control, then PATCHes status ...
#   GET  /runs/{id}/logs                   -> assert the marker line came back
#   GET  /runs/{id}                        -> assert status flipped to "succeeded"
#
# Why echo and not claude: resolveAgentCommand() honors run.Command first, so the
# smoke run needs neither the agent binary nor an OpenRouter key — only an image
# whose PATH has `echo`. Keeps the test deterministic and free.
#
# This is an INTEGRATION test against live infra — it cannot run in plain CI. It
# needs a reachable staging control plane and that backend needs real GCP creds.
#
# ---------------------------------------------------------------------------
# Driver-side env (this script):
#   LANCER_STAGING_URL    public base URL of the staging control plane
#                          (e.g. http://35.201.3.231:8080)
#   LANCER_CLIENT_TOKEN   a valid, ACTIVE entitlement client token in staging
#                          (Authorization: Bearer — customerId is derived server-side)
# Optional:
#   SMOKE_TIMEOUT_SECS     overall poll budget (default 240 — Cloud Run cold start
#                          + image pull can take a few minutes on first run)
#   SMOKE_POLL_SECS        poll interval (default 5)
#   SMOKE_KEEP             set to 1 to skip cancel/cleanup on failure (for debugging)
#
# Flags:
#   --cleanup-agent        on exit, also DELETE the ephemeral smoke agent (and its
#                          provisioned Cloud Run Job) so repeated runs don't pile up
#                          orphan agents. Off by default — the agent is left in place,
#                          which is handy when debugging a failure. SMOKE_KEEP=1
#                          overrides this and leaves everything for inspection.
#
# Backend-side prerequisites the smoke test VALIDATES by failing if absent — verify
# these on the staging deployment BEFORE blaming the test:
#   GCP_PROJECT                 set (else Launch returns "GCP_PROJECT not configured")
#   GCP_CLOUD_RUN_IMAGE         a REAL lancer runner image whose entrypoint is the
#                               agent-runner binary. The code default is
#                               gcr.io/cloudrun/hello, which has NO runner — a run
#                               against it never calls back and this test times out.
#   CONTROL_PLANE_PUBLIC_URL    publicly reachable by GCP (NOTE: this is a different
#                               var from PUBLIC_BASE_URL used elsewhere; dispatchRun
#                               fails fast with "CONTROL_PLANE_PUBLIC_URL is not set"
#                               if it is missing — the run goes straight to failed).
#   GCP ADC credentials with run.jobs.run + run.executions.cancel permissions.
# ---------------------------------------------------------------------------
set -euo pipefail

CLEANUP_AGENT=0
for arg in "$@"; do
  case "$arg" in
    --cleanup-agent) CLEANUP_AGENT=1 ;;
    -h|--help) sed -n '2,60p' "$0"; exit 0 ;;
    *) echo "unknown arg: $arg" >&2; exit 2 ;;
  esac
done

: "${LANCER_STAGING_URL:?set LANCER_STAGING_URL (e.g. http://35.201.3.231:8080)}"
: "${LANCER_CLIENT_TOKEN:?set LANCER_CLIENT_TOKEN (an active staging entitlement token)}"
TIMEOUT="${SMOKE_TIMEOUT_SECS:-240}"
POLL="${SMOKE_POLL_SECS:-5}"
BASE="${LANCER_STAGING_URL%/}"
AUTH="Authorization: Bearer ${LANCER_CLIENT_TOKEN}"

command -v jq  >/dev/null || { echo "FATAL: jq is required"; exit 2; }
command -v curl >/dev/null || { echo "FATAL: curl is required"; exit 2; }

# Unique marker so concurrent/previous runs can't produce a false positive.
NONCE="$(date +%s)-$$-${RANDOM}"
MARKER="lancer-gcp-smoke-${NONCE}"

say()  { printf '\033[1;36m›\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m✗ FAIL:\033[0m %s\n' "$*" >&2; exit 1; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$*"; }

# curl wrapper: prints body, fails the script on non-2xx with the status + body.
api() {
  local method="$1" path="$2" body="${3:-}" tmp http
  tmp="$(mktemp)"
  if [[ -n "$body" ]]; then
    http="$(curl -sS -o "$tmp" -w '%{http_code}' -X "$method" "$BASE$path" \
            -H "$AUTH" -H 'Content-Type: application/json' -d "$body")"
  else
    http="$(curl -sS -o "$tmp" -w '%{http_code}' -X "$method" "$BASE$path" -H "$AUTH")"
  fi
  cat "$tmp"; rm -f "$tmp"
  [[ "$http" =~ ^2 ]] || { echo; fail "$method $path -> HTTP $http"; }
}

# --- 0. Liveness -----------------------------------------------------------
say "Health check: $BASE/health"
curl -sS -f "$BASE/health" >/dev/null || fail "staging /health not reachable"
ok "staging control plane is up"

# --- 1. Create a gcp_cloud_run agent (provisions a real Cloud Run Job) ------
say "Creating gcp_cloud_run agent…"
AGENT_JSON="$(api POST /agents "$(jq -nc --arg n "smoke-$NONCE" \
  '{name:$n, runtime:"gcp_cloud_run", description:"ephemeral GCP smoke agent"}')")"
AGENT_ID="$(jq -r '.id' <<<"$AGENT_JSON")"
[[ "$AGENT_ID" == agent_* ]] || fail "no agent id in response: $AGENT_JSON"
# Surface the provisioning status the backend recorded so a bad image/creds shows here.
PROV_STATUS="$(jq -r '.config.gcpCloudRun.status // "unknown"' <<<"$AGENT_JSON" 2>/dev/null || echo unknown)"
ok "agent $AGENT_ID provisioned (gcpCloudRun.status=$PROV_STATUS)"
[[ "$PROV_STATUS" == "submit_failed" ]] && fail "Cloud Run Job creation failed at provision time — check GCP creds/image"

cleanup() {
  [[ "${SMOKE_KEEP:-0}" == "1" ]] && { say "SMOKE_KEEP=1 — leaving agent $AGENT_ID / run ${RUN_ID:-none} for inspection"; return; }
  # Cancel the run first; DELETE /agents refuses (409) while a run is non-terminal.
  [[ -n "${RUN_ID:-}" ]] && curl -sS -X POST "$BASE/runs/$RUN_ID/cancel" -H "$AUTH" >/dev/null 2>&1 || true
  if [[ "$CLEANUP_AGENT" == "1" && -n "${AGENT_ID:-}" ]]; then
    # Cancel is cooperative — wait briefly for the run to go terminal so the
    # agent-delete guard lets us through, then best-effort delete (tears down the Job).
    for _ in 1 2 3 4 5 6; do
      [[ -z "${RUN_ID:-}" ]] && break
      st="$(curl -sS "$BASE/runs/$RUN_ID" -H "$AUTH" 2>/dev/null | jq -r '.status // ""' || true)"
      case "$st" in succeeded|failed|cancelled|"") break ;; esac
      sleep 5
    done
    code="$(curl -sS -o /dev/null -w '%{http_code}' -X DELETE "$BASE/agents/$AGENT_ID" -H "$AUTH" 2>/dev/null || echo 000)"
    if [[ "$code" == "200" ]]; then say "cleanup: deleted smoke agent $AGENT_ID"; else say "cleanup: agent delete returned HTTP $code (manual cleanup may be needed)"; fi
  fi
  return 0
}
trap cleanup EXIT

# --- 2. Create a run with a marker command ---------------------------------
say "Creating run (command: echo $MARKER)…"
RUN_JSON="$(api POST /runs "$(jq -nc --arg a "$AGENT_ID" --arg c "echo $MARKER" \
  '{agentId:$a, command:$c}')")"
RUN_ID="$(jq -r '.id' <<<"$RUN_JSON")"
[[ "$RUN_ID" == run_* ]] || fail "no run id in response: $RUN_JSON"
ok "run $RUN_ID created (status=$(jq -r '.status' <<<"$RUN_JSON"))"

# --- 3. Poll for the marker line AND a terminal status ---------------------
say "Polling up to ${TIMEOUT}s for marker + terminal status…"
deadline=$(( $(date +%s) + TIMEOUT ))
saw_marker=0; final_status=""
while (( $(date +%s) < deadline )); do
  LOGS="$(curl -sS "$BASE/runs/$RUN_ID/logs?since=0" -H "$AUTH" || echo '{}')"
  if jq -e --arg m "$MARKER" '.lines[]?|select(.text|contains($m))' >/dev/null 2>&1 <<<"$LOGS"; then
    saw_marker=1
  fi
  RUN="$(curl -sS "$BASE/runs/$RUN_ID" -H "$AUTH" || echo '{}')"
  st="$(jq -r '.status // ""' <<<"$RUN")"
  case "$st" in
    succeeded|failed|cancelled) final_status="$st"; break ;;
  esac
  printf '  …status=%-9s marker=%s\n' "${st:-?}" "$([[ $saw_marker == 1 ]] && echo yes || echo no)"
  sleep "$POLL"
done

# --- 4. Assert -------------------------------------------------------------
echo
[[ "$saw_marker" == 1 ]] || fail "marker '$MARKER' never appeared in run logs (image lacks agent-runner? control-plane URL unreachable from GCP? CONTROL_PLANE_PUBLIC_URL unset?)"
ok "marker line streamed back from the real Cloud Run container"
[[ -n "$final_status" ]] || fail "run never reached a terminal status within ${TIMEOUT}s (runner hung / never launched)"
[[ "$final_status" == "succeeded" ]] || fail "run terminal status was '$final_status', expected 'succeeded' (echo exit 0)"
ok "run $RUN_ID terminal status = succeeded"

echo
ok "GCP Cloud Run smoke test PASSED — full cloud pipeline verified end-to-end"
