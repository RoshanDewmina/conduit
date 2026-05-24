# conduitd

The Conduit daemon that runs on the remote host and bridges agent approval
events to the iOS app via a JSON-RPC stdio channel.

## Build

```bash
# For local testing on macOS:
swift build -c release

# Cross-compile for Linux arm64 (requires Swift cross-compilation toolchain):
swift build -c release --triple aarch64-unknown-linux-gnu

# Or use Docker:
docker run --rm -v $(pwd):/src swift:5.10 \
  swift build -c release --package-path /src
```

## Install on remote host

```bash
scp .build/release/conduitd user@host:~/.conduit/bin/conduitd
ssh user@host chmod +x ~/.conduit/bin/conduitd
```

## Usage

```bash
# Start the JSON-RPC server (called by the iOS app via SSH exec):
conduitd serve --stdio

# Print version:
conduitd version

# Send an approval event from a Claude Code hook:
conduitd agent-hook approval \
  --agent claude-code \
  --kind command \
  --command "rm -rf /tmp/old-build" \
  --cwd /home/user/project \
  --risk medium
```

## Hook integration (Claude Code)

Create `~/.claude/hooks/pre-tool.sh`:
```bash
#!/bin/bash
~/.conduit/bin/conduitd agent-hook approval \
  --agent claude-code \
  --kind command \
  --command "$CLAUDE_TOOL_COMMAND" \
  --cwd "$PWD" \
  --risk "${CLAUDE_RISK_LEVEL:-medium}"
```
