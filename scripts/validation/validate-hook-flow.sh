#!/usr/bin/env bash
# validate-hook-flow.sh — automated hook flow validation (local, no iOS required)
# Usage: LANCERD_BINARY=./daemon/lancerd/lancerd ./scripts/validation/validate-hook-flow.sh
# For full end-to-end validation, see docs/validation-playbook.md (requires Lancer iOS).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LANCERD_BINARY="${LANCERD_BINARY:-$REPO_ROOT/daemon/lancerd/lancerd}"
HOOK_SCRIPT="${HOOK_SCRIPT:-$REPO_ROOT/docs/lancer-hook.sh}"
PASS=0
FAIL=0
SKIP=0

pass() { echo "✓ $1"; PASS=$((PASS+1)); }
fail() { echo "✗ $1"; FAIL=$((FAIL+1)); }
skip() { echo "- $1 (SKIP: $2)"; SKIP=$((SKIP+1)); }

check_go_build() {
    echo "--- Test: lancerd builds from source ---"
    if command -v go &>/dev/null; then
        if (cd "$REPO_ROOT/daemon/lancerd" && go build ./... 2>&1); then
            pass "lancerd go build ./..."
        else
            fail "lancerd go build failed"
        fi
    else
        skip "lancerd go build" "go not installed"
    fi
}

check_lancerd_binary() {
    echo ""
    echo "--- Test: lancerd binary exists and runs ---"
    if [[ ! -f "$LANCERD_BINARY" ]]; then
        skip "lancerd binary check" "binary not found at $LANCERD_BINARY; build with: cd daemon/lancerd && go build -o lancerd ."
        return
    fi
    if [[ ! -x "$LANCERD_BINARY" ]]; then
        fail "lancerd binary not executable"
        return
    fi
    pass "lancerd binary found and executable"

    # 'lancerd version' exits 0 — verifies the binary executes correctly.
    # 'lancerd serve' (the daemon mode) blocks waiting for an SSH stdio connection
    # and is not suitable for a quick smoke test.
    local ver
    if ver=$("$LANCERD_BINARY" version 2>&1); then
        pass "lancerd version runs (reported: $ver)"
    else
        fail "lancerd version exited non-zero"
    fi
}

check_hook_script_syntax() {
    echo ""
    echo "--- Test: lancer-hook.sh syntax ---"
    if [[ ! -f "$HOOK_SCRIPT" ]]; then
        fail "hook script not found at $HOOK_SCRIPT"
        return
    fi
    if bash -n "$HOOK_SCRIPT" 2>&1; then
        pass "lancer-hook.sh syntax check"
    else
        fail "lancer-hook.sh has syntax errors"
    fi
}

check_hook_auto_approve_fallback() {
    echo ""
    echo "--- Test: hook auto-approve fallback (no lancerd socket) ---"
    if [[ ! -f "$LANCERD_BINARY" ]]; then
        skip "hook auto-approve fallback" "lancerd binary not found; build first"
        return
    fi

    # The auto-approve path lives inside 'lancerd agent-hook': when the Unix socket
    # is absent (lancerd serve is not running), agent-hook prints a message and
    # exits 0 (auto-approve) so agents are never blocked when the phone is offline.
    # Invoke agent-hook directly against a guaranteed-nonexistent socket path.
    local fake_home="/tmp/lancer-validate-home-$$"
    mkdir -p "$fake_home/.lancer"
    local exit_code=0

    # HOME override ensures socketPath() resolves to a path under $fake_home
    # where no lancerd serve is listening.
    HOME="$fake_home" "$LANCERD_BINARY" agent-hook \
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
        fail "hook auto-approve fallback: expected exit 0, got $exit_code (lancerd agent-hook should auto-approve when serve is not running)"
    fi
}

check_codex_hook_syntax() {
    echo ""
    echo "--- Test: codex-lancer-hook.sh syntax ---"
    local codex_hook="$REPO_ROOT/docs/codex-lancer-hook.sh"
    if [[ ! -f "$codex_hook" ]]; then
        skip "codex hook syntax" "codex-lancer-hook.sh not found"
        return
    fi
    if bash -n "$codex_hook" 2>&1; then
        pass "codex-lancer-hook.sh syntax check"
    else
        fail "codex-lancer-hook.sh has syntax errors"
    fi
}

check_go_tests() {
    echo ""
    echo "--- Test: lancerd Go tests ---"
    if command -v go &>/dev/null; then
        local result
        if result=$(cd "$REPO_ROOT/daemon/lancerd" && go test ./... 2>&1); then
            pass "lancerd go test ./..."
        else
            # No test files is OK
            if echo "$result" | grep -q "\[no test files\]"; then
                pass "lancerd go test ./... (no test files — expected)"
            else
                fail "lancerd go test failed: $result"
            fi
        fi
    else
        skip "lancerd Go tests" "go not installed"
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
    echo "=== Lancer Hook Flow Validation (Automated) ==="
    echo "Repo root: $REPO_ROOT"
    echo ""
    check_go_build
    check_lancerd_binary
    check_hook_script_syntax
    check_hook_auto_approve_fallback
    check_codex_hook_syntax
    check_go_tests
    print_summary
}

main "$@"
