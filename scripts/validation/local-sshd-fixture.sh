#!/usr/bin/env bash
# local-sshd-fixture.sh — validate and configure local sshd for Lancer hook testing
# Usage: ./scripts/validation/local-sshd-fixture.sh
# Prereq: macOS (Remote Login must be enabled in System Settings)
set -euo pipefail

FIXTURE_KEY="/tmp/lancer-test-ed25519"
LANCER_KEYCHAIN_SERVICE="lancer-localhost-ssh"

check_remote_login() {
    local status
    if ! status=$(sudo systemsetup -getremotelogin 2>/dev/null); then
        echo "ERROR: Could not check Remote Login status (may need sudo)."
        echo "Enable manually: System Settings → General → Sharing → Remote Login: ON"
        echo "Or: sudo systemsetup -setremotelogin on"
        exit 1
    fi
    if ! echo "$status" | grep -qi "on"; then
        echo "ERROR: macOS Remote Login is not enabled."
        echo "Enable it: System Settings → General → Sharing → Remote Login: ON"
        echo "Or: sudo systemsetup -setremotelogin on"
        exit 1
    fi
    echo "✓ Remote Login is enabled"
}

generate_test_key() {
    if [[ ! -f "$FIXTURE_KEY" ]]; then
        ssh-keygen -t ed25519 -f "$FIXTURE_KEY" -N "" -q
        echo "✓ Test key generated at $FIXTURE_KEY"
    else
        echo "✓ Test key already exists at $FIXTURE_KEY"
    fi
}

authorize_test_key() {
    mkdir -p ~/.ssh && chmod 700 ~/.ssh
    local pubkey
    pubkey=$(cat "${FIXTURE_KEY}.pub")
    touch ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys
    if ! grep -qF "$pubkey" ~/.ssh/authorized_keys; then
        echo "$pubkey" >> ~/.ssh/authorized_keys
        echo "✓ Test key added to ~/.ssh/authorized_keys"
    else
        echo "✓ Test key already in ~/.ssh/authorized_keys"
    fi
}

test_ssh_connection() {
    local output
    if output=$(ssh -i "$FIXTURE_KEY" \
        -o StrictHostKeyChecking=no \
        -o BatchMode=yes \
        -o ConnectTimeout=5 \
        "$(whoami)@127.0.0.1" "echo 'SSH_OK'" 2>&1); then
        if echo "$output" | grep -q "SSH_OK"; then
            echo "✓ SSH to 127.0.0.1 works"
        else
            echo "ERROR: SSH connected but got unexpected output: $output"
            exit 1
        fi
    else
        echo "ERROR: SSH to 127.0.0.1 failed: $output"
        echo "Ensure Remote Login is enabled and the test key is authorized."
        exit 1
    fi
}

print_lancer_keychain_setup() {
    echo ""
    echo "--- Lancer iOS keychain entry (run once) ---"
    echo "Lancer iOS needs your macOS login password to SSH to 127.0.0.1."
    echo "Store it in the macOS Keychain so the fixture test can find it:"
    echo ""
    echo "  security add-generic-password \\"
    echo "    -s '$LANCER_KEYCHAIN_SERVICE' \\"
    echo "    -a '$(whoami)' \\"
    echo "    -w 'YOUR_MACOS_LOGIN_PASSWORD' \\"
    echo "    -U"
    echo ""
    echo "To verify: security find-generic-password -s '$LANCER_KEYCHAIN_SERVICE' -w"
}

main() {
    echo "=== Lancer Local sshd Fixture ==="
    check_remote_login
    generate_test_key
    authorize_test_key
    test_ssh_connection
    print_lancer_keychain_setup
    echo ""
    echo "=== Fixture ready ==="
    echo "  Host:       127.0.0.1"
    echo "  User:       $(whoami)"
    echo "  SSH key:    $FIXTURE_KEY"
    echo "  Bundle ID:  dev.lancer.mobile"
    echo ""
    echo "Next: build and install the Lancer app on a simulator, then follow"
    echo "docs/validation-playbook.md for the live approval loop tests."
}

main "$@"
