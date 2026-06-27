# Lancer Validation Playbook

> **For the full guided bring-up + notification proof, use [`LIVE_LOOP_RUNBOOK.md`](LIVE_LOOP_RUNBOOK.md).**
> This playbook is the lower-level automated/manual test-case reference (TC-1..TC-7). Note: the
> "Known limitations" table below is partly **stale** — allow-always now persists
> (`policy-always.yaml`) and lancerd POSTs approvals to push-backend; the open gap is
> **physical-device APNs while the app is closed** (runbook Phase 5c).

Tests the hook → lancerd → iOS Inbox → Allow/Reject golden path.

## What's automated vs manual

| Check | Automated | Requires |
|-------|-----------|----------|
| lancerd builds from Go source | yes | Go toolchain |
| lancerd starts and runs | yes | lancerd binary |
| Hook script syntax | yes | bash |
| Hook auto-approve fallback | yes | bash |
| Go tests | yes | Go toolchain |
| Full hook → iOS round-trip | TODO(owner) | Lancer iOS + live host |
| Allow once / Reject behaviors | TODO(owner) | Lancer iOS + live host |
| Always-approve persistence | TODO(owner) | Lancer iOS + live host + WS-C/WS-D implemented |
| Reconnect recovery | TODO(owner) | Lancer iOS + live host |
| OSC 133 on bash/zsh/fish | TODO(owner) | Live SSH session |

---

## Automated validation

### 1. Build lancerd
```bash
cd daemon/lancerd
go build -o lancerd .
go test ./...
cd ../..
```

### 2. Run automated checks
```bash
chmod +x scripts/validation/validate-hook-flow.sh
LANCERD_BINARY=./daemon/lancerd/lancerd \
HOOK_SCRIPT=./docs/lancer-hook.sh \
./scripts/validation/validate-hook-flow.sh
```

### 2b. Resident daemon smoke (command-center)
```bash
chmod +x scripts/validation/resident-bridge-smoke.sh
cd daemon/lancerd && go build -o lancerd .
LANCERD_BINARY=./lancerd ../../scripts/validation/resident-bridge-smoke.sh
```

Covers: fail-closed `command` hook with daemon down, resident socket up, attach client, `agent.audit.tail` RPC.

All automated checks should PASS (or SKIP if tools missing). Any FAIL is a regression.

### 3. Validate local sshd fixture (for local iOS simulator testing)
```bash
chmod +x scripts/validation/local-sshd-fixture.sh
./scripts/validation/local-sshd-fixture.sh
```

Follow the on-screen instructions to store your macOS login password in Keychain for the Lancer app.

---

## Live approval loop tests — TODO(owner)

These require:
- Lancer iOS built and running on a simulator or physical iPhone
- lancerd running on the target host (or localhost via local-sshd-fixture.sh)
- Claude Code hooks configured on the target host

### Setup (run once)

```bash
# 1. Start lancerd on target host (or localhost)
./daemon/lancerd/lancerd &

# 2. Install Claude Code hook
cp docs/lancer-hook.sh ~/.claude/hooks/lancer-hook.sh
chmod +x ~/.claude/hooks/lancer-hook.sh

# 3. Configure Claude Code hooks (add to ~/.claude/settings.json):
# {
#   "hooks": {
#     "PreToolUse": [
#       {
#         "hooks": [
#           {
#             "type": "command",
#             "command": "~/.claude/hooks/lancer-hook.sh"
#           }
#         ]
#       }
#     ]
#   }
# }
# See docs/claude-settings-hook.json for reference.

# 4. Open Lancer iOS → connect to the host → navigate to Inbox tab
# 5. Keep Lancer in foreground
```

### TC-1: Reject blocks tool execution
```bash
claude 'write the text "reject-test" to /tmp/lancer-tc1.txt'
```
- Lancer iOS shows pending approval in Inbox
- Tap **Reject**
- Verify: `cat /tmp/lancer-tc1.txt` → "No such file or directory"
- **PASS** if file not created; **FAIL** if file exists

### TC-2: Allow once permits execution
```bash
claude 'write the text "allow-test" to /tmp/lancer-tc2.txt'
```
- Lancer iOS shows pending approval in Inbox
- Tap **Allow**
- Verify: `cat /tmp/lancer-tc2.txt` → "allow-test"
- **PASS** if file contains correct content; **FAIL** otherwise

### TC-3: Allow always (aspirational — requires WS-C + WS-D)
> **NOTE:** This test will FAIL until WS-C (structured tool_use wire protocol) and WS-D (always-approve persistence) are implemented. DaemonChannel.swift currently collapses .approvedAlways → "approve" without persisting the rule. Document this as a known gap.

```bash
claude 'write the text "first" to /tmp/lancer-tc3a.txt'
# Tap "Allow always" in Lancer iOS Inbox
claude 'write the text "second" to /tmp/lancer-tc3b.txt'
# Expected: auto-approved, no Inbox prompt
```
- **PASS** if second call auto-approved without prompt
- **KNOWN FAIL** until WS-C/WS-D are implemented

### TC-4: Reconnect recovery
1. Start `claude 'write the text "reconnect" to /tmp/lancer-tc4.txt'` on the target host
2. While approval is pending: force-quit Lancer iOS or kill the SSH connection
3. Reopen Lancer iOS → reconnect to the host
4. Check Inbox
- **PASS** if: reconnect works cleanly, no stale approvals, agent eventually times out gracefully
- **FAIL** if: crash, infinite spinner, or corrupt Inbox state

### TC-5: Ctrl-C mid-approval
1. Start `claude` with a file-write task
2. While approval is pending in Inbox: on the remote shell, press Ctrl-C
3. Check Lancer iOS Inbox
- **PASS** if: pending approval resolves (timeout exit code 1); Inbox clears; no crash
- **FAIL** if: Inbox stuck, crash, or agent hangs indefinitely

### TC-6: OSC 133 block formation on real shells
On the target host:
```bash
# For bash
source ~/.lancer/lancer-shell-init.sh  # if available

# Or use the bundled hook directly
claude 'list the files in /tmp'
```
- In Lancer iOS session view, observe the block for the `ls` command
- **PASS** if: command output appears as a clean block (A→C→D markers parsed); no raw escape codes visible
- **FAIL** if: output bleeds outside block or escape codes visible

### TC-7: Codex approval loop
Wire the Codex hook:
```bash
cp docs/codex-lancer-hook.sh ~/.codex/hooks/lancer-hook.sh
chmod +x ~/.codex/hooks/lancer-hook.sh
# Add docs/codex-hooks.json to your Codex config
```
Then:
1. Run `codex` → give it a file-write task
2. In Lancer iOS Inbox → Reject → verify file not created
3. Run again → Allow → verify file created
- **PASS** if: same behavior as TC-1/TC-2 but with Codex
- **FAIL** if: approval not received or decision not honored

---

## Known limitations (document, don't fake)

| Limitation | Status | Fixes in |
|-----------|--------|----------|
| Always-approve not persisted | DaemonChannel.swift collapses .approvedAlways → "approve"; no rules.go | WS-D |
| Structured tool input not available | lancer-hook.sh flattens tool_input to 500-char string | WS-C |
| Token-routing mismatch | iOS registers push with identifierForVendor; lancerd keys by agent session | WS-H |
| APNs alert loop open | lancerd never POSTs to push-backend | WS-H |
| fish shell | Not tested (fish not installed on typical CI host) | TODO |
| Physical device APNs | APNs only works on physical device, not simulator | Requires hardware |

---

## Regression criteria

After any code change to SessionFeature, lancerd, or the hook scripts:
1. Run `./scripts/validation/validate-hook-flow.sh` — all automated checks must PASS
2. If touching approval flow: manually run TC-1 + TC-2 on local sshd fixture
3. If touching lancerd: `cd daemon/lancerd && go build ./... && go test ./...`
