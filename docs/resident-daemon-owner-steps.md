# Resident daemon (`conduitd daemon`) — owner steps

The resident bridge keeps approval state and the Unix socket alive while your phone is disconnected. SSH sessions run `conduitd serve`, which **attaches** to the resident instead of owning the socket.

## Prerequisites

- Go 1.22+ (or a prebuilt `conduitd` binary)
- macOS or Linux host
- SSH from Conduit iOS to the host

## Install binary and service

From the repo (or after copying `conduitd` to the host):

```bash
cd daemon/conduitd
go build -o conduitd .
./conduitd install
```

`install` writes:

- Binary: `~/.conduit/bin/conduitd`
- macOS: `~/Library/LaunchAgents/dev.conduit.conduitd.plist` (runs `conduitd daemon`)
- Linux: `~/.config/systemd/user/conduitd.service`

### macOS — enable launchd

```bash
launchctl unload ~/Library/LaunchAgents/dev.conduit.conduitd.plist 2>/dev/null || true
launchctl load ~/Library/LaunchAgents/dev.conduit.conduitd.plist
```

Verify:

```bash
ls -l ~/.conduit/conduitd.sock
~/.conduit/bin/conduitd version
```

### Linux — enable systemd user unit

```bash
systemctl --user daemon-reload
systemctl --user enable --now conduitd.service
systemctl --user status conduitd.service
```

## Runtime layout

| Path | Mode | Purpose |
|------|------|---------|
| `~/.conduit/conduitd.sock` | socket | Agent hooks + `serve` attach |
| `~/.conduit/queue.json` | 0600 | Pending approvals when no phone attached |
| `~/.conduit/bin/conduitd` | 0755 | Installed binary |

## Hook fail-closed behavior

If the resident daemon is **not** running, mutating tool kinds (`command`, `patch`, `fileWrite`, etc.) **hold** (exit 1) instead of auto-approving.

Optional read-only fail-open (off by default):

```bash
export CONDUIT_HOOK_READONLY_FAIL_OPEN=1
```

Only kinds `read`, `grep`, `list`, `search` may fail-open when the flag is set.

## Manual verification (local)

1. `conduitd install` and start the service (steps above).
2. Confirm socket: `test -S ~/.conduit/conduitd.sock`.
3. Run an agent hook while **no** SSH session is attached — check `~/.conduit/queue.json` contains the event.
4. Connect from the app (SSH `conduitd serve`) — pending cards should drain.
5. Stop the resident — mutating hook should print *holding mutating action* and exit 1.

## TODO(owner)

- End-to-end validation with **live SSH + local-sshd fixture** per `docs/validation-playbook.md` (when present on your branch).
- APNs push while detached is handled in WS-D; resident queue covers bridge persistence now.
