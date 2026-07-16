# Resident daemon (`lancerd daemon`) — owner steps

**Last updated: 2026-07-15.**

The resident bridge keeps approval state and the Unix socket alive while your phone is disconnected. SSH sessions run `lancerd serve`, which **attaches** to the resident instead of owning the socket.

## Prerequisites

- Go 1.22+ (or a prebuilt `lancerd` binary)
- macOS or Linux host
- SSH from Lancer iOS to the host

## Golden path (copy-paste)

```bash
cd daemon/lancerd && go build -o lancerd .
./lancerd install
# macOS:
launchctl load ~/Library/LaunchAgents/dev.lancer.lancerd.plist
# Linux:
systemctl --user enable --now lancerd.service
test -S ~/.lancer/lancerd.sock && ~/.lancer/bin/lancerd version
```

Point agent hooks at the installed binary (not a repo-relative path):

| Agent | Hook install |
|-------|----------------|
| Claude Code | `cp docs/lancer-hook.sh ~/.claude/hooks/lancer-hook.sh && chmod 700 ~/.claude/hooks/lancer-hook.sh` |
| Codex | `cp docs/codex-lancer-hook.sh ~/.config/codex/hooks/lancer-hook.sh` (see `docs/codex-hooks.json`) |
| OpenCode | `mkdir -p ~/.config/opencode/hooks && cp docs/opencode-lancer-hook.sh ~/.config/opencode/hooks/lancer-hook.sh && chmod 700 ~/.config/opencode/hooks/lancer-hook.sh && cp docs/opencode-hooks.json ~/.config/opencode/hooks.json` |

Policy files (bridge evaluates these before asking the phone):

| Path | Purpose |
|------|---------|
| `~/.lancer/policy.yaml` | Global default policy |
| `<repo>/.lancer/policy.yaml` | Repo-local overrides (walked from hook `cwd`) |
| `~/.lancer/audit.log` | JSONL audit of auto + human decisions (mode 0600) |

Automated smoke (no iOS):

```bash
cd daemon/lancerd && go build -o lancerd .
LANCERD_BINARY=./lancerd ../scripts/validation/resident-bridge-smoke.sh
```

## Install binary and service

From the repo (or after copying `lancerd` to the host):

```bash
cd daemon/lancerd
go build -o lancerd .
./lancerd install
```

`install` writes:

- Binary: `~/.lancer/bin/lancerd`
- macOS: `~/Library/LaunchAgents/dev.lancer.lancerd.plist` (runs `lancerd daemon`)
- Linux: `~/.config/systemd/user/lancerd.service`

### macOS — enable launchd

```bash
launchctl unload ~/Library/LaunchAgents/dev.lancer.lancerd.plist 2>/dev/null || true
launchctl load ~/Library/LaunchAgents/dev.lancer.lancerd.plist
```

Verify:

```bash
ls -l ~/.lancer/lancerd.sock
~/.lancer/bin/lancerd version
```

### Linux — enable systemd user unit

```bash
systemctl --user daemon-reload
systemctl --user enable --now lancerd.service
systemctl --user status lancerd.service
```

## Runtime layout

| Path | Mode | Purpose |
|------|------|---------|
| `~/.lancer/lancerd.sock` | socket | Agent hooks + `serve` attach |
| `~/.lancer/queue.json` | 0600 | Pending approvals when no phone attached |
| `~/.lancer/bin/lancerd` | 0755 | Installed binary |

## Hook fail-closed behavior

If the resident daemon is **not** running, mutating tool kinds (`command`, `patch`, `fileWrite`, etc.) **hold** (exit 1) instead of auto-approving.

Optional read-only fail-open (off by default):

```bash
export LANCER_HOOK_READONLY_FAIL_OPEN=1
```

Only kinds `read`, `grep`, `list`, `search` may fail-open when the flag is set.

## Manual verification (local)

1. `lancerd install` and start the service (steps above).
2. Confirm socket: `test -S ~/.lancer/lancerd.sock`.
3. Run an agent hook while **no** SSH session is attached — check `~/.lancer/queue.json` contains the event.
4. Connect from the app (SSH `lancerd serve`) — pending cards should drain.
5. Stop the resident — mutating hook should print *holding mutating action* and exit 1.

## TODO(owner)

- End-to-end validation with **live SSH + local-sshd fixture** per
  `docs/LIVE_LOOP_RUNBOOK.md` (Phases 1–4) and `docs/PUBLISH_READINESS_CHECKLIST.md` (C1).
  (Former `docs/validation-playbook.md` was purged — do not recreate.)
- APNs push while detached is delivered by the deployed `push-backend` (live); resident
  `queue.json` covers bridge persistence when the phone is offline. A real-device smoke test
  is the only open item — see `docs/PUBLISH_READINESS_CHECKLIST.md` C2 / D3.
