# lancerd

`lancerd` is the self-host bridge between Lancer iOS and remote AI coding agents.

It runs on your host/VM, receives pre-tool hook events from agents (Claude Code, Codex),
and forwards approval requests to the phone over the existing SSH channel.

## Runtime Model

```
iOS app <-- SSH stdio (JSON-RPC, framed) --> lancerd serve
                                                 ^
                                                 | unix socket (~/.lancer/lancerd.sock)
                                                 |
                                       lancerd agent-hook (from agent hooks)
```

- `lancerd serve`: long-running daemon process launched over SSH by the app.
- `lancerd agent-hook`: short-lived command called by CLI hook scripts.
- If `serve` is not available, hook mode auto-approves so your local workflow is not blocked.

## Requirements

- Go 1.22+
- Linux or macOS host
- SSH access from your iPhone to the host

## Build

```bash
cd daemon/lancerd
go build -o lancerd .
```

Cross-compile examples:

```bash
CGO_ENABLED=0 GOOS=linux  GOARCH=amd64 go build -o lancerd-linux-amd64 .
CGO_ENABLED=0 GOOS=linux  GOARCH=arm64 go build -o lancerd-linux-arm64 .
CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 go build -o lancerd-darwin-arm64 .
```

## Install (Self-Host)

### Fast path installer

From repo root:

```bash
daemon/lancerd/install.sh --hooks both
```

By default this installs:
- binary: `~/.lancer/bin/lancerd`
- Claude hook: `~/.claude/hooks/lancer-hook.sh`
- Codex hook: `~/.codex/hooks/lancer-hook.sh`
- Codex hook config: `~/.codex/hooks.json`

### Manual install

```bash
mkdir -p ~/.lancer/bin
cp daemon/lancerd/lancerd ~/.lancer/bin/lancerd
chmod 755 ~/.lancer/bin/lancerd
~/.lancer/bin/lancerd version
```

## Hook Setup

### Claude Code

1. Copy `docs/lancer-hook.sh` to `~/.claude/hooks/lancer-hook.sh`
2. `chmod 700 ~/.claude/hooks/lancer-hook.sh`
3. Wire it in `~/.claude/settings.json` (see `docs/claude-settings-hook.json`)

### Codex

1. Copy `docs/codex-lancer-hook.sh` to `~/.codex/hooks/lancer-hook.sh`
2. `chmod 700 ~/.codex/hooks/lancer-hook.sh`
3. Copy `docs/codex-hooks.json` to `~/.codex/hooks.json`
4. Trust hook configuration in Codex (`/hooks`)

## Environment Variables

- `LANCERD`: override path to daemon binary in hook scripts (default `~/.lancer/bin/lancerd`)
- `INSTALL_DIR`: override install destination for `daemon/lancerd/install.sh`

## Optional Service Snippets

Use these if you want `lancerd serve` managed as a host service. This is optional;
Lancer can also launch `lancerd serve` over SSH on-demand.

### systemd (`~/.config/systemd/user/lancerd.service`)

```ini
[Unit]
Description=Lancer bridge daemon

[Service]
ExecStart=%h/.lancer/bin/lancerd serve
Restart=always
RestartSec=2

[Install]
WantedBy=default.target
```

Enable:

```bash
systemctl --user daemon-reload
systemctl --user enable --now lancerd.service
```

### launchd (`~/Library/LaunchAgents/dev.lancer.lancerd.plist`)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key><string>dev.lancer.lancerd</string>
    <key>ProgramArguments</key>
    <array>
      <string>/Users/YOUR_USER/.lancer/bin/lancerd</string>
      <string>serve</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
  </dict>
</plist>
```

Enable:

```bash
launchctl unload ~/Library/LaunchAgents/dev.lancer.lancerd.plist 2>/dev/null || true
launchctl load ~/Library/LaunchAgents/dev.lancer.lancerd.plist
```

## Release Packaging

Build tarballs for distribution:

```bash
scripts/release-lancerd.sh v0.1.0
```

Artifacts are written to `daemon/lancerd/dist/`.

## Protocol Notes

Frames: `[uint32 big-endian length][JSON body]`

Daemon receives:
- `ping`
- `agent.approval.response`

Daemon emits:
- `agent.approval.pending`

`ApprovalEvent` includes structured fields (`toolName`, `toolUseID`, `sessionID`, `toolInput`)
when hooks provide them, enabling richer approval cards and safer rule matching.
