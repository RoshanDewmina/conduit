#!/usr/bin/env bash
# Lane C4 live harness — post-Wave-1 sweep re-test on tip 7707e4fa.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SWEEP_DIR=/tmp/sweep-C4
LOG_DIR="$ROOT/docs/test-runs/2026-07-16-untested-feature-sweep"
DAEMON_BIN=/tmp/lancerd-sweep-C4
RESULT_BUNDLE=/tmp/sweep-C4/C4.xcresult

rm -rf "$SWEEP_DIR"
mkdir -p "$SWEEP_DIR/target-repo"
(
  cd "$SWEEP_DIR/target-repo"
  git init -q
  echo "hello" > greeting.txt
  echo "readme" > readme.md
  git add -A
  git commit -q -m init
)

echo "== build daemon =="
(cd "$ROOT/daemon/lancerd" && go build -o "$DAEMON_BIN" .)

echo "== start isolated daemon =="
pkill -f "lancerd-sweep-C4 daemon" 2>/dev/null || true
sleep 1
LANCER_STATE_DIR="$SWEEP_DIR" "$DAEMON_BIN" daemon >"$SWEEP_DIR/daemon.log" 2>&1 &
DAEMON_PID=$!
echo "$DAEMON_PID" >"$SWEEP_DIR/daemon.pid"
for _ in $(seq 1 30); do
  [[ -S "$SWEEP_DIR/lancerd.sock" ]] && break
  sleep 0.5
done
if [[ ! -S "$SWEEP_DIR/lancerd.sock" ]]; then
  echo "FAIL: daemon sock missing" >&2
  tail -50 "$SWEEP_DIR/daemon.log" >&2
  exit 1
fi

echo "== pair =="
PAIR_OUT=$(LANCER_STATE_DIR="$SWEEP_DIR" "$DAEMON_BIN" pair 2>&1)
echo "$PAIR_OUT" | tee "$SWEEP_DIR/pair.log"
PAIR_CODE=$(echo "$PAIR_OUT" | rg -o '[0-9]{6}' | head -1)
if [[ -z "${PAIR_CODE:-}" ]]; then
  echo "FAIL: no pair code" >&2
  exit 1
fi
echo "PAIR_CODE=$PAIR_CODE"

echo "== simurgh lease =="
LEASE_JSON=$(simurgh acquire --model "iPhone 17 Pro" --rm --json)
LEASE_ID=$(python3 -c "import json,sys; print(json.load(sys.stdin)['lease']['id'])" <<<"$LEASE_JSON")
UDID=$(python3 -c "import json,sys; print(json.load(sys.stdin)['lease']['device']['udid'])" <<<"$LEASE_JSON")
DD=$(python3 -c "import json,sys; print(json.load(sys.stdin)['lease']['env']['env']['SIMURGH_DERIVED_DATA'])" <<<"$LEASE_JSON")
echo "LEASE=$LEASE_ID UDID=$UDID"

cleanup() {
  simurgh release "$LEASE_ID" --force 2>/dev/null || true
  if [[ -f "$SWEEP_DIR/daemon.pid" ]]; then
    kill "$(cat "$SWEEP_DIR/daemon.pid")" 2>/dev/null || true
  fi
}
trap cleanup EXIT

echo "== xcodegen =="
(cd "$ROOT" && xcodegen generate)

echo "== build-for-testing =="
simurgh exec "$LEASE_ID" -- xcodebuild \
  -project "$ROOT/Lancer.xcodeproj" \
  -scheme Lancer \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath "$DD" \
  -only-testing:LancerUITests/SweepLaneC4Tests \
  build-for-testing 2>&1 | tee "$SWEEP_DIR/build.log"

echo "== test =="
export TEST_RUNNER_LANE_C4_PAIR_CODE="$PAIR_CODE"
simurgh exec "$LEASE_ID" -- xcodebuild \
  -project "$ROOT/Lancer.xcodeproj" \
  -scheme Lancer \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath "$DD" \
  -resultBundlePath "$RESULT_BUNDLE" \
  -only-testing:LancerUITests/SweepLaneC4Tests/testLaneC4_PostWave1LiveSweep \
  test-without-building 2>&1 | tee "$SWEEP_DIR/test-run.log"

echo "== extract screenshots =="
mkdir -p "$LOG_DIR/screenshots"
if [[ -d "$RESULT_BUNDLE" ]]; then
  xcrun xcresulttool get attachments --path "$RESULT_BUNDLE" 2>/dev/null || true
fi

echo "DONE lease=$LEASE_ID pair=$PAIR_CODE"
