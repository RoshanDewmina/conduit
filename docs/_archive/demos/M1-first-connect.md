# M1 — First Connect

Status: complete
Created: 2026-05-23T17:05:35Z
Updated: 2026-05-24

## Goal

Prove that the iOS app can connect to a real SSH host with secure host-key handling and either password or Ed25519 key authentication.

## Current App Support

- Add a host from onboarding or Workspaces.
- Choose password auth or an Ed25519 key generated in Settings > SSH Keys.
- Password auth prompts at connect time and is not stored.
- Ed25519 auth loads the selected key from `KeyStore`.
- Host keys are validated through `HostKeyStore` using TOFU.
- Unknown host keys are recorded automatically for now; explicit user confirmation is still required before M1 is complete.

## Demo Script

1. Generate an Ed25519 key in Settings > SSH Keys.
2. Copy the public key and install it on the remote host:

   ```bash
   mkdir -p ~/.ssh
   chmod 700 ~/.ssh
   printf '%s\n' '<paste public key>' >> ~/.ssh/authorized_keys
   chmod 600 ~/.ssh/authorized_keys
   ```

3. Add the host in Lancer:
   - name: short display name
   - hostname: DNS name or IP
   - port: 22 unless the host differs
   - username: remote username
   - auth: password or Ed25519 key

4. Tap the host.
5. For password auth, enter the password when prompted.
6. Confirm the app reaches the Session tab and reports connected.
7. Run:

   ```bash
   pwd
   ls -la
   ls /definitely-missing
   ```

8. Verify:
   - successful commands create rendered blocks;
   - the failing command records a non-zero exit code;
   - reconnect does not bypass host-key validation;
   - changing the server host key fails with a host-key mismatch.

## Pass Criteria

| Scenario | Expected |
|---|---|
| First connect — Ed25519 | Face ID gate → TOFU sheet → connect |
| Second connect — Ed25519 | No Face ID re-prompt, no TOFU sheet |
| First connect — password | Password sheet → connect |
| Wrong password | `.failed` banner |
| Host key mismatch | `.failed(reason: "Host key changed …")` banner |

## Not Done (deferred)

- Raw PTY mode for shells, `tmux`, `vim`, `htop`, and other TUI programs.
- Persisted last-connected host timestamp update after successful connect.
- Integration harness for repeatable SSH auth and host-key mismatch tests.
