#!/usr/bin/env bash
set -uo pipefail

# relay-approval-e2e.sh — prove the FULL V1 relay approval round-trip in the sim:
# phone (XCUITest) ↔ production Fly relay ↔ resident lancerd, tap APPROVE,
# host hook unblocks (exit 0) + audit shows `approve`, then dispatch → lancer.proof/v0
# receipt via the same paired daemon (control-channel probe).
#
# Why a host harness + XCUITest (not pure idb): synthesized HID taps don't fire
# SwiftUI buttons on this headless iOS-27 sim, but XCUITest event injection does.
# The XCUITest (TapInjectionProofTests.testRelayApprovalUnblocksHostHook) drives
# the phone side; this script drives the daemon + escalation + assertions.
#
# Prereqs: a booted iPhone sim, lancerd built. No SSH / Remote Login needed —
# this is the relay path, not SSH.

REPO="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../.." && pwd)"
RELAY_BASE="${LANCER_RELAY_URL:-wss://conduit-push.fly.dev}"
BACKEND="${LANCER_PUSH_BACKEND_URL:-https://conduit-push.fly.dev}"
# Fresh random code per run. Reusing a fixed code (314159) against the shared
# relay let leaked daemons from PREVIOUS runs — each with its own keypair —
# fight the current run's daemon for the same pair slot, which is how the
# 2026-07-07 silent approval-delivery losses happened. A per-run code also
# coexists with the relay's key pinning, which hard-rejects a second key on a
# reused code.
CODE="${LANCER_RELAY_CODE:-$(printf '%06d' $(((RANDOM * 32768 + RANDOM) % 1000000)))}"
ISO="/tmp/lancer-relay-e2e/home"
LOG="/tmp/lancer-relay-e2e/daemon.log"
HOOK_LOG="/tmp/lancer-relay-e2e/hook.log"
MARKER="/tmp/lancer-relay-e2e/approve-marker.txt"
BUNDLE="dev.lancer.mobile"
SIM="${LANCER_SIM_NAME:-iPhone 17 Pro}"
# Pin to a specific sim UDID (multiple sims may be booted → `booted` is ambiguous).
UDID="${LANCER_SIM_UDID:-$(xcrun simctl list devices booted | grep -i "$SIM" | grep -oE '[0-9A-Fa-f-]{36}' | head -1)}"
LANCERD="$REPO/daemon/lancerd/lancerd"

cleanup() { kill "${DAEMON_PID:-}" "${HOOK_PID:-}" 2>/dev/null; }
trap cleanup EXIT

# Kill daemons/hooks leaked by interrupted previous runs BEFORE wiping state —
# a stale daemon keeps reconnecting to the relay and steals the pair slot from
# this run's daemon (exact-path match so the user's resident
# ~/.lancer/bin/lancerd is never touched).
pkill -f "^$LANCERD daemon" 2>/dev/null
pkill -f "^$LANCERD agent-hook" 2>/dev/null
sleep 1

rm -rf /tmp/lancer-relay-e2e; mkdir -p "$ISO/.lancer"
rm -f "$MARKER"

echo "=== build lancerd ==="
( cd "$REPO/daemon/lancerd" && go build -o lancerd . ) || { echo "FAIL: lancerd build"; exit 1; }

echo "=== default-ask policy (fileWrite escalates) ==="
cat > "$ISO/.lancer/policy.yaml" <<'YAML'
rules:
  - id: allow-echo
    effect: allow
    match: "echo*"
  - id: deny-rmrf
    effect: deny
    match: "rm -rf*"
YAML

echo "=== clean app inbox state (uninstall so no stale pending cards) ==="
xcrun simctl uninstall "$UDID" "$BUNDLE" 2>/dev/null || true
# The sim keychain survives uninstall: each prior run's debug-seam pairing
# leaves an orphaned private key that hydrates as a ghost "re-pair required"
# machine on every launch (22 accumulated by 2026-07-08). Reset for a truly
# hermetic run.
xcrun simctl keychain "$UDID" reset 2>/dev/null || true

echo "=== start resident daemon (isolated HOME, production relay) ==="
HOME="$ISO" LANCER_RELAY_URL="$RELAY_BASE" LANCER_RELAY_E2E_FAKE_DISPATCH=1 \
  APPROVAL_RELAY_SECRET="${APPROVAL_RELAY_SECRET:-}" "$LANCERD" daemon >"$LOG" 2>&1 &
DAEMON_PID=$!
sleep 2
HOME="$ISO" LANCER_RELAY_URL="$RELAY_BASE" "$LANCERD" relay-attach "$CODE" >/dev/null 2>&1
echo "  daemon pid $DAEMON_PID, code $CODE, relay $RELAY_BASE"

# Wait for the daemon's own relay socket to connect before we hand the code to
# the app — and FAIL if it doesn't (this loop used to fall through silently,
# letting a run without any relay-connected daemon proceed to a guaranteed,
# misleading downstream failure).
DAEMON_UP=0
for i in $(seq 1 15); do grep -q "connected to relay as daemon" "$LOG" && { DAEMON_UP=1; break; }; sleep 1; done
if [ "$DAEMON_UP" != 1 ]; then
  echo ">>> FAIL: daemon never connected to the relay within 15s — see $LOG"
  tail -10 "$LOG"
  exit 1
fi

echo "=== launch XCUITest (builds+installs+runs; app pairs via LANCER_RELAY_CODE) ==="
# TEST_RUNNER_* env is forwarded to the XCUITest runner (prefix stripped), where
# the test copies it into app.launchEnvironment.
#
# -derivedDataPath is pinned to a harness-private directory OUTSIDE
# /tmp/lancer-relay-e2e (which this script rm -rf's on every run) rather than
# the shared per-project DerivedData: concurrent xcodebuild activity elsewhere
# on the machine races the same build.db and fails with "database is locked".
TEST_RUNNER_LANCER_RELAY_E2E=1 \
TEST_RUNNER_LANCER_RELAY_URL="$RELAY_BASE" \
TEST_RUNNER_LANCER_RELAY_CODE="$CODE" \
TEST_RUNNER_LANCER_PUSH_BACKEND_URL="$BACKEND" \
xcodebuild test \
  -project "$REPO/Lancer.xcodeproj" -scheme Lancer \
  -destination "id=$UDID" \
  -derivedDataPath /tmp/lancer-relay-e2e-derived-data \
  -only-testing:LancerUITests/TapInjectionProofTests/testRelayApprovalUnblocksHostHook \
  >/tmp/lancer-relay-e2e/xcodebuild.log 2>&1 &
XCB_PID=$!

echo "=== wait for app to PAIR with the daemon over the relay (up to 600s incl. build) ==="
PAIRED=0
for i in $(seq 1 300); do
  grep -q "paired with phone" "$LOG" && { PAIRED=1; break; }
  if ! kill -0 "$XCB_PID" 2>/dev/null; then
    echo "  xcodebuild exited before pairing completed"
    wait "$XCB_PID" || true
    echo ">>> FAIL: xcodebuild died before phone paired — see /tmp/lancer-relay-e2e/xcodebuild.log"
    exit 1
  fi
  sleep 2
done
if [ "$PAIRED" != 1 ]; then
  echo ">>> FAIL: phone never paired with daemon within 600s — see $LOG"
  kill "$XCB_PID" 2>/dev/null || true
  wait "$XCB_PID" 2>/dev/null || true
  exit 1
fi
echo "  PAIRED ✓"
echo "=== wait for relay XCUITest to start (build finished, app on Inbox) ==="
for i in $(seq 1 180); do
  grep -q "Test Case.*testRelayApprovalUnblocksHostHook.*started" /tmp/lancer-relay-e2e/xcodebuild.log 2>/dev/null && break
  if ! kill -0 "$XCB_PID" 2>/dev/null; then break; fi
  sleep 2
done
sleep 5

echo "=== fire fileWrite escalation (blocks awaiting the phone's decision) ==="
HOME="$ISO" "$LANCERD" agent-hook \
  --agent claudeCode --kind fileWrite \
  --command "$MARKER" --cwd "/tmp/lancer-relay-e2e" --risk medium \
  >"$HOOK_LOG" 2>&1 &
HOOK_PID=$!
echo "  hook pid $HOOK_PID (the XCUITest will tap APPROVE)"

echo "=== wait for the XCUITest to finish ==="
wait "$XCB_PID"; XCB_RC=$?

echo "=== wait for the hook to return (decision rode the relay back) ==="
for i in $(seq 1 150); do kill -0 "$HOOK_PID" 2>/dev/null || break; sleep 1; done
HOOK_RC="(still blocking)"
if ! kill -0 "$HOOK_PID" 2>/dev/null; then wait "$HOOK_PID"; HOOK_RC=$?; fi

echo "=== receipt probe (fake dispatch → lancer.proof/v0 on paired daemon) ==="
RECEIPT_RC=1
if [ "$XCB_RC" = 0 ] && [ "$HOOK_RC" = 0 ]; then
  (
    cd "$REPO/daemon/lancerd" && \
    HOME="$ISO" LANCER_RELAY_E2E_RECEIPT_PROBE=1 \
      go test -run TestRelayE2EReceiptAfterPairedDaemon -count=1 .
  ) >/tmp/lancer-relay-e2e/receipt-probe.log 2>&1
  RECEIPT_RC=$?
  if [ "$RECEIPT_RC" = 0 ]; then
    echo "  RECEIPT ✓ (schema lancer.proof/v0, contract echoed)"
  else
    echo "  RECEIPT ✗ — see /tmp/lancer-relay-e2e/receipt-probe.log"
    tail -20 /tmp/lancer-relay-e2e/receipt-probe.log
  fi
else
  echo "  RECEIPT skipped (approval round-trip did not pass)"
fi

echo ""
echo "================= RESULT ================="
echo "xcodebuild test rc : $XCB_RC  (0 = APPROVE tapped + card cleared)"
echo "agent-hook rc      : $HOOK_RC (0 = host hook UNBLOCKED via relay approve)"
echo "receipt probe rc   : $RECEIPT_RC (0 = lancer.proof/v0 via agent.run.receipt.get)"
echo "--- audit tail ---"; tail -2 "$ISO/.lancer/audit.log" 2>/dev/null || echo "(no audit)"
echo "--- marker file created by the unblocked agent? ---"
[ -f "$MARKER" ] && echo "YES ($MARKER)" || echo "NO (agent did not run a real write — expected: hook only gates, agent would create it)"
echo "--- xcodebuild tail (on failure) ---"
[ "$XCB_RC" != 0 ] && tail -25 /tmp/lancer-relay-e2e/xcodebuild.log

if [ "$XCB_RC" = 0 ] && [ "$HOOK_RC" = 0 ] && [ "$RECEIPT_RC" = 0 ]; then
  echo ">>> PASS: relay approval + receipt round-trip proven (phone tap → relay → receipt)."
  exit 0
fi
echo ">>> FAIL: see logs in /tmp/lancer-relay-e2e/"
exit 1
