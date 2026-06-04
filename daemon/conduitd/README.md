# conduitd

`conduitd` is the self-host bridge between Conduit iOS and remote AI coding agents.

It runs on your host/VM, receives pre-tool hook events from agents (Claude Code, Codex),
and forwards approval requests to the phone over the existing SSH channel.

## Runtime Model

```
iOS app <-- SSH stdio (JSON-RPC, framed) --> conduitd serve
                                                 ^
                                                 | unix socket (~/.conduit/conduitd.sock)
                                                 |
                                       conduitd agent-hook (from agent hooks)
```

- `conduitd serve`: long-running daemon process launched over SSH by the app.
- `conduitd agent-hook`: short-lived command called by CLI hook scripts.
- If `serve` is not available, hook mode auto-approves so your local workflow is not blocked.

## Requirements

- Go 1.22+
- Linux or macOS host
- SSH access from your iPhone to the host

## Build

```bash
cd daemon/conduitd
go build -o conduitd .
```

Cross-compile examples:

```bash
CGO_ENABLED=0 GOOS=linux  GOARCH=amd64 go build -o conduitd-linux-amd64 .
CGO_ENABLED=0 GOOS=linux  GOARCH=arm64 go build -o conduitd-linux-arm64 .
CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 go build -o conduitd-darwin-arm64 .
```

## Install (Self-Host)

### Fast path installer

From repo root:

```bash
daemon/conduitd/install.sh --hooks both
```

By default this installs:
- binary: `~/.conduit/bin/conduitd`
- Claude hook: `~/.claude/hooks/conduit-hook.sh`
- Codex hook: `~/.codex/hooks/conduit-hook.sh`
- Codex hook config: `~/.codex/hooks.json`

### Manual install

```bash
mkdir -p ~/.conduit/bin
cp daemon/conduitd/conduitd ~/.conduit/bin/conduitd
chmod 755 ~/.conduit/bin/conduitd
~/.conduit/bin/conduitd version
```

## Hook Setup

### Claude Code

1. Copy `docs/conduit-hook.sh` to `~/.claude/hooks/conduit-hook.sh`
2. `chmod 700 ~/.claude/hooks/conduit-hook.sh`
3. Wire it in `~/.claude/settings.json` (see `docs/claude-settings-hook.json`)

### Codex

1. Copy `docs/codex-conduit-hook.sh` to `~/.codex/hooks/conduit-hook.sh`
2. `chmod 700 ~/.codex/hooks/conduit-hook.sh`
3. Copy `docs/codex-hooks.json` to `~/.codex/hooks.json`
4. Trust hook configuration in Codex (`/hooks`)

## Environment Variables

- `CONDUITD`: override path to daemon binary in hook scripts (default `~/.conduit/bin/conduitd`)
- `INSTALL_DIR`: override install destination for `daemon/conduitd/install.sh`

## Optional Service Snippets

Use these if you want `conduitd serve` managed as a host service. This is optional;
Conduit can also launch `conduitd serve` over SSH on-demand.

### systemd (`~/.config/systemd/user/conduitd.service`)

```ini
[Unit]
Description=Conduit bridge daemon

[Service]
ExecStart=%h/.conduit/bin/conduitd serve
Restart=always
RestartSec=2

[Install]
WantedBy=default.target
```

Enable:

```bash
systemctl --user daemon-reload
systemctl --user enable --now conduitd.service
```

### launchd (`~/Library/LaunchAgents/dev.conduit.conduitd.plist`)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key><string>dev.conduit.conduitd</string>
    <key>ProgramArguments</key>
    <array>
      <string>/Users/YOUR_USER/.conduit/bin/conduitd</string>
      <string>serve</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
  </dict>
</plist>
```

Enable:

```bash
launchctl unload ~/Library/LaunchAgents/dev.conduit.conduitd.plist 2>/dev/null || true
launchctl load ~/Library/LaunchAgents/dev.conduit.conduitd.plist
```

## Release Packaging

Build tarballs for distribution:

```bash
scripts/release-conduitd.sh v0.1.0
```

Artifacts are written to `daemon/conduitd/dist/`.

## Protocol Notes

Frames: `[uint32 big-endian length][JSON body]`

Daemon receives:
- `ping`
- `agent.approval.response`

Daemon emits:
- `agent.approval.pending`

`ApprovalEvent` includes structured fields (`toolName`, `toolUseID`, `sessionID`, `toolInput`)
when hooks provide them, enabling richer approval cards and safer rule matching.
