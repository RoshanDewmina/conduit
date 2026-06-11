# conduitd resident bridge (WS-A)

The resident daemon keeps approval state and the Unix socket alive across SSH sessions. The iOS app still runs `conduitd serve` over SSH stdio; `serve` attaches to the resident and relays framed JSON-RPC.

## Layout

| Path | Purpose |
|------|---------|
| `~/.conduit/conduitd.sock` | Unix socket (hooks + attach) |
| `~/.conduit/queue.json` | Pending approvals when no attach client (mode `0600`) |
| `~/.conduit/always-rules.json` | Allow-always rules from the phone |
| `~/.conduit/bin/conduitd` | Binary installed by `conduitd install` |

Set `CONDUIT_STATE_DIR` to override `~/.conduit` (tests and multi-user hosts).

## Commands

```bash
conduitd daemon    # persistent resident (launchd/systemd)
conduitd serve     # attach to resident, or self-host with stderr warning
conduitd install   # copy binary + write launchd/systemd unit
conduitd agent-hook ...
```

## Install (macOS)

```bash
go build -o ~/.conduit/bin/conduitd ./daemon/conduitd
~/.conduit/bin/conduitd install
launchctl load ~/Library/LaunchAgents/dev.conduit.conduitd.plist
```

## Install (Linux, user systemd)

```bash
~/.conduit/bin/conduitd install
systemctl --user enable --now conduitd.service
```

## Hook fail-closed

When the resident is not reachable, **mutating** tool kinds (`patch`, `fileWrite`, `network`, unknown kinds, etc.) exit **1** and block the agent. Shell `command` is not treated as mutating for this gate.

Read-only kinds (`grep`, `read`, …) fail-open only if `CONDUIT_HOOK_READONLY_FAIL_OPEN=1`.

## SSH session flow

1. `conduitd daemon` runs at login (launchd/systemd).
2. iOS SSH runs `conduitd serve` → attach handshake `{"op":"attach"}` → bidirectional framed JSON-RPC.
3. Agent hooks dial `~/.conduit/conduitd.sock` with a raw JSON `ApprovalEvent`.
4. If the phone is disconnected, events are queued in `queue.json` and drained on the next attach.

## Audit

Human/auto decisions are appended to `~/.conduit/audit.log`. The attach client forwards JSON-RPC (including `agent.audit.tail`, `agent.policy.get` / `reload` / `set`) through the same framed stdio path as `conduitd serve`.

## Decision relay (decide while detached)

When the phone is not attached over SSH, approval decisions reach the resident via push-backend instead of the framed socket:

1. conduitd escalates → `postApprovalPush` POSTs `/approval` (APNs alert) AND the poller is already running (started at `conduit.device.register`).
2. The phone POSTs `POST /approval/decision { approvalId, decision, sessionId, editedToolInput? }`.
3. conduitd's `decisionPoller` GETs `/decisions?sessionId=…` every ~3s, draining decisions, and calls `approvalStore.resolve` — unblocking the waiting hook with no SSH session.
4. The SSH framed `agent.approval.response` path still works when attached; `resolve` is idempotent (first caller wins).

In-memory on the backend is sufficient — a decision only needs to outlive conduitd's 120 s approval wait.
