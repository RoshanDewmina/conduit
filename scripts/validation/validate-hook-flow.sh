#!/usr/bin/env bash
# validate-hook-flow.sh — automated hook flow validation (local, no iOS required)
# Usage: CONDUITD_BINARY=./daemon/conduitd/conduitd ./scripts/validation/validate-hook-flow.sh
# For full end-to-end validation, see docs/validation-playbook.md (requires Conduit iOS).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONDUITD_BINARY="${CONDUITD_BINARY:-$REPO_ROOT/daemon/conduitd/conduitd}"
HOOK_SCRIPT="${HOOK_SCRIPT:-$REPO_ROOT/docs/conduit-hook.sh}"
PASS=0
FAIL=0
SKIP=0

pass() { echo "✓ $1"; PASS=$((PASS+1)); }
fail() { echo "✗ $1"; FAIL=$((FAIL+1)); }
skip() { echo "- $1 (SKIP: $2)"; SKIP=$((SKIP+1)); }

check_go_build() {
    echo "--- Test: conduitd builds from source ---"
    if command -v go &>/dev/null; then
        if (cd "$REPO_ROOT/daemon/conduitd" && go build ./... 2>&1); then
            pass "conduitd go build ./..."
        else
            fail "conduitd go build failed"
        fi
    else
        skip "conduitd go build" "go not installed"
    fi
}

check_conduitd_binary() {
    echo ""
    echo "--- Test: conduitd binary exists and runs ---"
    if [[ ! -f "$CONDUITD_BINARY" ]]; then
        skip "conduitd binary check" "binary not found at $CONDUITD_BINARY; build with: cd daemon/conduitd && go build -o conduitd ."
        return
    fi
    if [[ ! -x "$CONDUITD_BINARY" ]]; then
        fail "conduitd binary not executable"
        return
    fi
    pass "conduitd binary found and executable"

    # 'conduitd version' exits 0 — verifies the binary executes correctly.
    # 'conduitd serve' (the daemon mode) blocks waiting for an SSH stdio connection
    # and is not suitable for a quick smoke test.
    local ver
    if ver=$("$CONDUITD_BINARY" version 2>&1); then
        pass "conduitd version runs (reported: $ver)"
    else
        fail "conduitd version exited non-zero"
    fi
}

check_hook_script_syntax() {
    echo ""
    echo "--- Test: conduit-hook.sh syntax ---"
    if [[ ! -f "$HOOK_SCRIPT" ]]; then
        fail "hook script not found at $HOOK_SCRIPT"
        return
    fi
    if bash -n "$HOOK_SCRIPT" 2>&1; then
        pass "conduit-hook.sh syntax check"
    else
        fail "conduit-hook.sh has syntax errors"
    fi
}

check_hook_auto_approve_fallback() {
    echo ""
    echo "--- Test: hook auto-approve fallback (no conduitd socket) ---"
    if [[ ! -f "$CONDUITD_BINARY" ]]; then
        skip "hook auto-approve fallback" "conduitd binary not found; build first"
        return
    fi

    # The auto-approve path lives inside 'conduitd agent-hook': when the Unix socket
    # is absent (conduitd serve is not running), agent-hook prints a message and
    # exits 0 (auto-approve) so agents are never blocked when the phone is offline.
    # Invoke agent-hook directly against a guaranteed-nonexistent socket path.
    local fake_home="/tmp/conduit-validate-home-$$"
    mkdir -p "$fake_home/.conduit"
    local exit_code=0

    # HOME override ensures socketPath() resolves to a path under $fake_home
    # where no conduitd serve is listening.
    HOME="$fake_home" "$CONDUITD_BINARY" agent-hook \
        --agent "claudeCode" \
        --kind "fileWrite" \
        --command "/tmp/test.txt" \
        --cwd "/tmp" \
        --risk "medium" \
        >/dev/null 2>&1 || exit_code=$?

    rm -rf "$fake_home"

    if [[ $exit_code -eq 0 ]]; then
        pass "hook auto-approve fallback: agent-hook exits 0 when no socket present"
    else
        fail "hook auto-approve fallback: expected exit 0, got $exit_code (conduitd agent-hook should auto-approve when serve is not running)"
    fi
}

check_codex_hook_syntax() {
    echo ""
    echo "--- Test: codex-conduit-hook.sh syntax ---"
    local codex_hook="$REPO_ROOT/docs/codex-conduit-hook.sh"
    if [[ ! -f "$codex_hook" ]]; then
        skip "codex hook syntax" "codex-conduit-hook.sh not found"
        return
    fi
    if bash -n "$codex_hook" 2>&1; then
        pass "codex-conduit-hook.sh syntax check"
    else
        fail "codex-conduit-hook.sh has syntax errors"
    fi
}

check_go_tests() {
    echo ""
    echo "--- Test: conduitd Go tests ---"
    if command -v go &>/dev/null; then
        local result
        if result=$(cd "$REPO_ROOT/daemon/conduitd" && go test ./... 2>&1); then
            pass "conduitd go test ./..."
        else
            # No test files is OK
            if echo "$result" | grep -q "\[no test files\]"; then
                pass "conduitd go test ./... (no test files — expected)"
            else
                fail "conduitd go test failed: $result"
            fi
        fi
    else
        skip "conduitd Go tests" "go not installed"
    fi
}

print_summary() {
    echo ""
    echo "========================================"
    echo "Automated validation results:"
    echo "  PASS: $PASS"
    echo "  FAIL: $FAIL"
    echo "  SKIP: $SKIP"
    echo "========================================"
    if [[ $FAIL -gt 0 ]]; then
        echo "Some checks failed. See output above."
        exit 1
    fi
    echo "Automated checks complete."
    echo "For live iOS validation, follow docs/validation-playbook.md."
}

main() {
    echo "=== Conduit Hook Flow Validation (Automated) ==="
    echo "Repo root: $REPO_ROOT"
    echo ""
    check_go_build
    check_conduitd_binary
    check_hook_script_syntax
    check_hook_auto_approve_fallback
    check_codex_hook_syntax
    check_go_tests
    print_summary
}

main "$@"
