#!/usr/bin/env bash
# test_hook_pipeline.sh — end-to-end shell test for the conduit-hook.sh pipeline.
#
# Run from the repo root:
#   bash daemon/conduitd/test_hook_pipeline.sh
#
# Or from this directory:
#   bash test_hook_pipeline.sh
#
# Exits 0 on pass, 1 on failure.
#
# What it tests:
#   - conduit-hook.sh reads tool_name, tool_use_id, session_id, and tool_input
#     from stdin JSON (not from CLAUDE_* env vars)
#   - The mock conduitd stub receives the correct --tool-name, --tool-use-id,
#     --session-id, and --tool-input flags

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_SCRIPT="$(cd "$SCRIPT_DIR/../.." && pwd)/docs/conduit-hook.sh"
SAMPLE_JSON="$SCRIPT_DIR/testdata/sample-pretooluse.json"
MOCK_CONDUITD="$SCRIPT_DIR/testdata/mock-conduitd.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

pass() {
  printf 'PASS: %s\n' "$1"
}

# Sanity-check files exist
[ -f "$HOOK_SCRIPT" ]    || fail "hook script not found: $HOOK_SCRIPT"
[ -f "$SAMPLE_JSON" ]    || fail "sample JSON not found: $SAMPLE_JSON"
[ -x "$MOCK_CONDUITD" ]  || fail "mock conduitd not executable: $MOCK_CONDUITD"

# Run the hook with mock conduitd; capture output
OUTPUT=$(CONDUITD="$MOCK_CONDUITD" bash "$HOOK_SCRIPT" < "$SAMPLE_JSON" 2>&1)
EXIT_CODE=$?

# The hook should exit 0 (mock conduitd always approves)
[ "$EXIT_CODE" -eq 0 ] || fail "hook exited $EXIT_CODE (expected 0). Output: $OUTPUT"
pass "hook exited 0"

# Check --tool-name
echo "$OUTPUT" | grep -q -- '--tool-name=Bash' \
  || fail "--tool-name=Bash not found in conduitd args. Got: $OUTPUT"
pass "--tool-name=Bash present"

# Check --tool-use-id
echo "$OUTPUT" | grep -q -- '--tool-use-id=toolu_abc123' \
  || fail "--tool-use-id=toolu_abc123 not found. Got: $OUTPUT"
pass "--tool-use-id=toolu_abc123 present"

# Check --session-id
echo "$OUTPUT" | grep -q -- '--session-id=sess_xyz789' \
  || fail "--session-id=sess_xyz789 not found. Got: $OUTPUT"
pass "--session-id=sess_xyz789 present"

# Check --tool-input contains the command
echo "$OUTPUT" | grep -q -- '--tool-input=' \
  || fail "--tool-input flag not found. Got: $OUTPUT"
pass "--tool-input present"

# Verify no CLAUDE_* env var leakage (the arg values must come from parsed stdin)
unset CLAUDE_TOOL_NAME CLAUDE_TOOL_USE_ID CLAUDE_SESSION_ID CLAUDE_TOOL_INPUT
OUTPUT2=$(CONDUITD="$MOCK_CONDUITD" bash "$HOOK_SCRIPT" < "$SAMPLE_JSON" 2>&1)
echo "$OUTPUT2" | grep -q -- '--tool-name=Bash' \
  || fail "Without CLAUDE_* env vars, --tool-name=Bash missing. Got: $OUTPUT2"
pass "fields come from stdin JSON, not CLAUDE_* env vars"

echo
echo "All tests passed."
exit 0
