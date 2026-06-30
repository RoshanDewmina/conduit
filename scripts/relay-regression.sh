#!/usr/bin/env bash
# relay-regression.sh — repeatable relay approval-loop regression test (simulator)
# Usage: ./scripts/relay-regression.sh
# Prereqs: macOS Remote Login on, SSH password in keychain, sim booted
set -euo pipefail

LANCER_KEYCHAIN_SERVICE="lancer-localhost-ssh"
SIM_NAME="iPhone 17 Pro"
BUNDLE_ID="dev.lancer.mobile"
DERIVED_DATA="/tmp/lancer-dd"
SCREENSHOT_DIR="/tmp/lancer-relay-regression"
SLEEP_AGENT=15

check_prereqs() {
  echo "--- Checking prerequisites ---"

  if ! xcrun simctl list devices booted | grep -q "Booted"; then
    echo "ERROR: No simulator is booted. Boot one first:"
    echo "  xcrun simctl boot \"$SIM_NAME\""
    exit 1
  fi
  echo "  Simulator is booted"

  if ! PW=$(security find-generic-password -s "$LANCER_KEYCHAIN_SERVICE" -w 2>/dev/null); then
    echo "ERROR: SSH password not found in keychain."
    echo "Store it:"
    echo "  security add-generic-password -s '$LANCER_KEYCHAIN_SERVICE' -a '$USER' -w 'YOUR_PW' -U"
    exit 1
  fi
  echo "  SSH password found in keychain"

  local status
  if ! status=$(sudo systemsetup -getremotelogin 2>/dev/null); then
    echo "ERROR: Could not check Remote Login. Enable it:"
    echo "  System Settings → General → Sharing → Remote Login: ON"
    echo "  Or: sudo systemsetup -setremotelogin on"
    exit 1
  fi
  if ! echo "$status" | grep -qi "on"; then
    echo "ERROR: Remote Login is not enabled."
    exit 1
  fi
  echo "  Remote Login is enabled"

  echo "--- All prerequisites met ---"
  echo ""
}

build_app() {
  echo "--- Building app for simulator ---"
  xcodebuild -project Lancer.xcodeproj -scheme Lancer \
    -destination "platform=iOS Simulator,name=$SIM_NAME" \
    -derivedDataPath "$DERIVED_DATA" build
  echo "  Build complete"
  echo ""
}

launch_session_harness() {
  echo "--- Launching live session regression seam ---"

  xcrun simctl terminate booted "$BUNDLE_ID" 2>/dev/null || true
  sleep 2

  xcrun simctl install booted "$DERIVED_DATA/Build/Products/Debug-iphonesimulator/Lancer.app"

  local PW
  PW=$(security find-generic-password -s "$LANCER_KEYCHAIN_SERVICE" -w)

  env \
    SIMCTL_CHILD_LANCER_DAEMON_E2E=1 \
    SIMCTL_CHILD_LANCER_DESTINATION=sessions \
    SIMCTL_CHILD_LANCER_TEST_HOST=127.0.0.1 \
    SIMCTL_CHILD_LANCER_TEST_USER="$USER" \
    SIMCTL_CHILD_LANCER_TEST_PW="$PW" \
    SIMCTL_CHILD_LANCER_TEST_PORT=22 \
    xcrun simctl launch booted "$BUNDLE_ID"

  echo "  App launched with LANCER_DAEMON_E2E=1 and LANCER_DESTINATION=sessions"
  echo "  Waiting ${SLEEP_AGENT}s for the localhost host to seed..."
  sleep "$SLEEP_AGENT"
  echo ""
}

take_screenshot() {
  local label="$1"
  local path="$SCREENSHOT_DIR/$label.png"
  mkdir -p "$SCREENSHOT_DIR"
  xcrun simctl io booted screenshot "$path"
  echo "  Screenshot saved: $path"
}

prompt_approval() {
  echo ""
  echo "============================================================"
  echo "  An approval card should now be visible in the Inbox."
  echo ""
  echo "  1. In the simulator, look for the pending approval"
  echo "     (it shows the command claude wants to run)."
  echo "  2. Tap 'Approve' on the card."
  echo ""
  echo "  Ready? Press Enter once you have approved (or rejected)."
  echo "============================================================"
  read -r
}

print_results() {
  echo ""
  echo "============================================================"
  echo "  Relay Regression Test — Results"
  echo "============================================================"
  echo "  Screenshots: $SCREENSHOT_DIR/"
  ls -1 "$SCREENSHOT_DIR/"
  echo ""
  echo "  Manual verification:"
  echo "    • before-approval.png — shows pending approval card"
  echo "    • after-approval.png  — shows decision result"
  echo ""
  echo "  Expected outcome:"
  echo "    • Before: Inbox has a pending approval card with the"
  echo "      agent's requested tool action"
  echo "    • After: Card transitions to DECIDED state (approved/rejected)"
  echo "    • The agent on the host unblocks and continues"
  echo ""
  echo "  If approval never appeared, check:"
  echo "    • The SSH daemon channel armed (session header shows green)"
  echo "    • lancerd is running on the host"
  echo "    • The policy engine escalated (not auto-allowed/denied)"
  echo "============================================================"
}

cleanup() {
  echo ""
  echo "--- Cleanup ---"
  xcrun simctl terminate booted "$BUNDLE_ID" 2>/dev/null || true
  echo "  App terminated"
}

main() {
  echo "=== Lancer Relay Regression Test ==="
  echo ""

  check_prereqs
  build_app
  launch_session_harness
  take_screenshot "before-approval"
  prompt_approval
  take_screenshot "after-approval"
  cleanup
  print_results
}

main "$@"
