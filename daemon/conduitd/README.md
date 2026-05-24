# conduitd

Remote daemon for Conduit — bridges the iOS app and AI agent hooks on your development machine.

## Architecture

```
iOS app ←── SSH stdio (JSON-RPC, length-framed) ──→ conduitd serve
                                                           ↕  Unix socket
                                              conduitd agent-hook  (Claude Code pre-tool hook)
```

- **`conduitd serve`** — runs on the remote host. The Conduit iOS app connects via SSH and
  spawns `conduitd serve` as a subprocess. Communication uses 4-byte big-endian length-prefixed
  JSON-RPC 2.0 frames over stdio.
- **`conduitd agent-hook`** — called by Claude Code's `~/.claude/hooks/pre-tool.sh`. Sends an
  approval event to the running `conduitd serve` via a Unix socket (`~/.conduit/conduitd.sock`),
  then blocks until the user approves or denies on their phone (or 120 s elapses, defaulting to
  auto-approve).

## Build

Requires Go 1.22+. Install with `brew install go` on macOS.

```bash
cd daemon/conduitd

# Local binary (macOS)
go build -o conduitd .

# Linux amd64 (most cloud VMs)
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o conduitd-linux-amd64 .

# Linux arm64 (Raspberry Pi, Graviton, Apple Silicon VMs)
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -o conduitd-linux-arm64 .
```

## Install on remote host

```bash
# Build the correct architecture first, e.g.:
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o conduitd-linux-amd64 .

# Copy to remote host
scp conduitd-linux-amd64 user@host:~/conduitd
ssh user@host "chmod +x ~/conduitd && ~/conduitd version"
```

## Claude Code hook integration

Add to `~/.claude/hooks/pre-tool.sh` on the remote host:

```bash
#!/bin/bash
~/conduitd agent-hook \
  --agent "claude-code" \
  --kind  "$CLAUDE_TOOL_NAME" \
  --command "$CLAUDE_TOOL_INPUT" \
  --cwd "$(pwd)" \
  --risk "medium"
```

Make it executable: `chmod +x ~/.claude/hooks/pre-tool.sh`

When `conduitd serve` is not running (phone disconnected), the hook auto-approves so agents
are never blocked when you're not actively supervising.

## Protocol

Frames: `[uint32 big-endian length][JSON body]`

| Method (iOS → daemon) | Description |
|---|---|
| `ping` | Keepalive; daemon replies `"pong"` |
| `agent.approval.response` | User approved/denied; params: `{approvalId, decision}` |

| Notification (daemon → iOS) | Description |
|---|---|
| `agent.approval.pending` | Agent hook is waiting; params: `ApprovalEvent` |

## Approval event schema

```json
{
  "approvalId": "uuid",
  "agent":      "claude-code",
  "kind":       "bash",
  "command":    "rm -rf /tmp/build",
  "cwd":        "/home/user/project",
  "risk":       "high",
  "timestamp":  "2026-05-24T12:00:00Z"
}
```
