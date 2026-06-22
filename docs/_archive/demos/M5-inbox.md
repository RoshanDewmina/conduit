# M5 — Inbox + Approvals Demo

## Prerequisites
- M1–M3 complete.
- Remote: `tmux`, `claude` (Claude Code CLI) installed and configured.
- `lancerd` binary deployed to `~/.lancer/bin/lancerd` on the remote host.
  Build: `swift build -c release` inside `daemon/lancerd/` then `scp`.
- Claude Code configured with approval hook:
  ```bash
  # ~/.claude/hooks/pre-tool.sh
  #!/bin/bash
  ~/.lancer/bin/lancerd agent-hook approval \
    --agent claude-code \
    --kind command \
    --command "$CLAUDE_TOOL_COMMAND" \
    --cwd "$PWD" \
    --risk "$CLAUDE_RISK_LEVEL"
  ```

## Steps

### 1. Connect and start daemon channel
Connect to host (M1 flow). `AppRoot.startSession` automatically starts `DaemonChannel` and `ApprovalIngest`.

Verify: Session tab connected, Inbox tab badge = 0.

### 2. Trigger an agent approval
In a remote tmux pane:
```
tmux new -s agent-test
claude "delete all .tmp files under ~/projects"
```
Claude Code evaluates the command; the pre-tool hook calls `lancerd agent-hook approval`.

**Expected within 1 s:**
- iOS Inbox tab badge increments to **1**.
- A local notification fires: "Claude Code needs approval".
- Opening Inbox: card shows agent="Claude Code", command=`find ~/projects -name "*.tmp" -delete`, risk band colour (medium or high).

### 3. Allow once
Tap **Allow once** on the card.

**Expected:**
- Card decision updates to "Approved" (green checkmark).
- `DaemonChannel.respond(approvalId:decision:.approved)` sends the response.
- Claude Code unblocks and executes the command.

### 4. Reject
Trigger another approval (e.g. `claude "rm -rf ~/tmp"`).

Tap **Reject**.

**Expected:**
- Card shows "Rejected" (red x).
- Claude Code receives rejection and aborts.

### 5. Notification action
Lock device. Trigger a new approval.

**Expected:** A banner/lock-screen notification appears with **Approve** / **Reject** action buttons.
Tapping **Approve** routes through `NotificationsKit` category handler → `ApprovalRepository`.

## Pass criteria
- [ ] `LancerDProtocolTests` + `DaemonChannelTests` pass.
- [ ] Approval appears in Inbox within 1 s of agent hook call.
- [ ] Allow once → agent unblocks.
- [ ] Reject → agent aborts.
- [ ] Notification action buttons work from lock screen.
