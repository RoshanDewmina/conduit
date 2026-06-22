# Runtime Ownership Map — Lancer for Mac

> Companion to `docs/architecture/macos-host-app-adr.md` and the plan at
> `~/.claude/plans/you-are-working-on-curried-pixel.md`. This document exists so there is exactly
> **one owner** for every piece of runtime state in the Lancer/Conduit system. `Lancer.app` (the
> new macOS management UI) must never become a second owner of anything `conduitd` already owns —
> it reads through IPC and renders. Paths below are verified against the code in
> `daemon/conduitd/` as of this writing (package `main`, binary `conduitd`).

## Ownership table

| Item | Owner | Where it lives | How Lancer.app accesses it |
|---|---|---|---|
| Active sessions (dispatched agent runs) | **conduitd** | In-memory in `dispatcher` (`daemon/conduitd/dispatch.go`); run lifecycle via `runDispatch`/`runContinue`/`applyRunControl` in `server.go:371-392` | Read-through IPC (`agent.dispatch`, `agent.run.continue`, `agent.cancel`/`pause`/`resume` RPCs over the resident socket) |
| Agent processes (spawned CLI children) | **conduitd** | OS child processes launched by `realLauncher` (`daemon/conduitd/dispatch.go:140`); controlled via `procHandle{kill,pause,resume}` | Read-through IPC only — Lancer.app never forks/kills agent processes itself; it asks conduitd via `agent.cancel`/`agent.pause`/`agent.resume` |
| PTYs / shim sessions | **conduitd** | `sessionRegistry` (`daemon/conduitd/session_registry.go:18`), keyed `ShimSession.ID`; spawned via `handleShimSpawnConn` (`resident.go:105-107`) | Read-through IPC (session list/status RPCs); no local PTY state in the app |
| Agent adapters (Claude/Codex/OpenCode/Kimi CLI integration) | **conduitd** | `agentArgv`/`continueArgv` in `daemon/conduitd/dispatch.go:33-108`; vendor `--version`/`--help` probing lives in the daemon, never the UI | Read-through IPC (`agent.status`, `agent.doctor`); installer only wires the Claude PreToolUse hook (`installClaudeHook`, `install.go:62`) — Lancer.app triggers that install step, it does not implement the adapter |
| Workspace access (filesystem listing under `$HOME`) | **conduitd** | `fsList` (`daemon/conduitd/fs.go:32`), confined to the user's home directory; git ops in `git.go` (`gitStatus`, `gitDiff`, `gitClone`, `gitShip`) | Read-through IPC (`agent.fs.ls`, `agent.git.*`) — Lancer.app never reads the filesystem directly on the daemon's behalf |
| Relay socket (E2E phone relay client) | **conduitd** | `e2eRouter`/`e2eRelayClient` wired in `resident.go:236-264` (`connectRelay`), config persisted at `~/.conduit/relay-pairing.json` (`relaypair.go:13-26`) | Read-through IPC for status (`agent.doctor`, `agent.host.health`); Lancer.app never opens or speaks the relay protocol itself |
| Direct connection listener | **conduitd owns its only listener (the Unix socket)** | `resident.listen()` binds `~/.conduit/conduitd.sock` (`resident.go:57-78`, `paths.go:32-38`). **Note:** "direct" connectivity from the phone is a separate SSH session to a pre-existing OS SSH server, not a listener conduitd opens — conduitd has no TCP/SSH listener of its own | Read-through IPC (`agent.doctor` / `agent.host.health` report direct-vs-relay reachability); Lancer.app never binds a competing socket |
| Device identity (this Mac's relay keypair) | **conduitd** | X25519 keypair persisted in `~/.conduit/relay-pairing.json` (`relaypair.go:13-18`, `writeRelayPairing`); account-device credential in `~/.conduit/account-device.json` (`account_device_pairing.go:105-123`) | Read-through IPC only — keys are never exported to or duplicated in the app; Lancer.app asks conduitd to pair, it does not generate or hold the keypair |
| Pairing keys / pairing flow | **conduitd** | `relayPairWatcher` polls `relay-pairing.json` for changes (`relaypair.go:59-133`); `conduitd pair` is the existing CLI entry point that writes this file | Read-through IPC — Lancer.app renders the QR/code conduitd produces (per the plan, "drive `conduitd pair` and render the QR + 6-digit code") and watches pairing status; it never writes `relay-pairing.json` itself |
| Provider credentials (API keys / secrets) | **conduitd** | `secretsStore`, persisted at `~/.conduit/secrets.json` (`secrets.go:15-21,75-78`); pending-request/authorize flow (`agent.secret.store/.request/.authorize/.revoke/.delete/.list` in `server.go:806-880`) | Read-through IPC only. Lancer.app never persists a secret value locally; `agent.secret.list` returns metadata (name/type/scope/use count), never raw `Value` |
| Policies (autonomy / approval rules) | **conduitd** | `policyEngine` (`server.go:41-177`); global policy at `policy.GlobalPolicyPath`, always-allow rules at `policy.AlwaysPolicyPath`, repo policy via `policy.LoadRepoPolicy`, all under the `daemon/conduitd/policy` package | Read-through IPC (`agent.policy.get/.set/.reload/.simulate`) — Lancer.app's Security pane edits policy YAML by sending it to `agent.policy.set`, never by writing policy files on disk |
| Approval state (pending/resolved decisions) | **conduitd** | `approvalStore` in-memory (`server.go:180`, referenced via `s.approvals`); durable mirror in `diskQueue` at `~/.conduit/queue.json` (`queue.go:9-18`, `resident.go:41-55,80-89`) | Read-through IPC (`agent.approval.response` to resolve; pending events delivered as notifications over the attach/relay channel) — Lancer.app never edits `queue.json` |
| Audit events | **conduitd** | Hash-chained JSONL log at `~/.conduit/audit.log` (`audit.go:49-56`), append-only via `auditLog.append`, every `AuditEntry` includes `Hash`/`PrevHash` | Read-through IPC (`agent.audit.tail`, `agent.audit.verify`, `agent.audit.export`) — Lancer.app never appends to or rewrites `audit.log` |
| Notifications (push / relay fan-out) | **conduitd** | `emitNotification` (`server.go:1264-1275`) fans out over the attach socket and, when paired, the E2E relay (`s.e2e.sendRelayNotification`); push registration via `postApprovalPush`/`postSecretRequestPush` (`server.go:1292-1342`) | Read-through IPC — Lancer.app subscribes to the same attach/notification stream conduitd already emits; it does not independently decide what to notify |
| Provider usage (spend / quota) | **conduitd** | `dispatcher`'s quota guard, fed by `collectAgentStatus` and updated via `updateProviderSpend` (`server.go:404-412,640-647`); caps set via `agent.quota.setCap` | Read-through IPC (`agent.quota.status`, `agent.status`) — Lancer.app renders spend, never tracks its own running total |
| **UI preferences** | **Lancer.app** | App-local `NSUserDefaults` (or equivalent) inside the app sandbox/container — not under `~/.conduit/` | UI-local — no IPC round-trip; this is the one piece of state the app legitimately owns end-to-end |
| Logs | **Split: conduitd owns daemon logs; Lancer.app owns app logs** | Daemon stdout/stderr redirected by the LaunchAgent plist to `~/.conduit/conduitd.stdout.log` / `conduitd.stderr.log` (`install.go:101-105`); app-side logs (UI crashes, app-level diagnostics) live wherever Lancer.app's own logging system writes (e.g. `OSLog`/`Console`, app container) | Daemon logs: read-through IPC where surfaced (`agent.doctor`) or installer-only file tail for support bundles; never written to by the app. App logs: UI-local, owned and written directly by Lancer.app |
| Updates | **Split: conduitd owns its own binary version; Lancer.app owns its own app update and orchestrates (does not own) service updates** | Daemon version reported via `collectDoctorReport`/`checkDaemonVersion` (`server.go:1466-1527`, `version` const); daemon binary lives at `~/.conduit/bin/conduitd` (`install.go:20-34`) | conduitd's own version: read-through IPC (`agent.doctor`). Service *update* (replacing the daemon binary, restarting the LaunchAgent) is installer-only — Lancer.app orchestrates this the same way `conduitd install` does today, but the resulting running version is still reported back through `agent.doctor`, not assumed by the app. The app's own update state (its bundle version, update-check state) is UI-local |

### Installer/lifecycle vs. runtime ownership — the distinction

Lancer.app **installs and manages the lifecycle** of conduitd and its LaunchAgent
(`~/Library/LaunchAgents/dev.conduit.conduitd.plist`, written by `installLaunchd` in
`install.go:84-114`): registering/unregistering the LaunchAgent (via `SMAppService` per the plan),
starting/stopping/restarting the process, detecting and adopting an existing standalone install,
running `conduitd doctor`, and uninstalling. **None of this makes Lancer.app the runtime owner.**
Once conduitd is running, every item in the table above — sessions, secrets, policy, audit, etc. —
is owned and persisted by conduitd under `~/.conduit/`, exactly as it is today for the iPhone
client. Quitting or crashing Lancer.app does not stop conduitd, and stopping conduitd is a
separate, explicit, explained action distinct from quitting the UI (per the plan's Phase A menu-bar
spec).

## Invariants

1. **The Mac UI is stateless across launches.** On every launch, Lancer.app reconstructs all
   runtime state (sessions, policy, approvals, devices, usage) by calling conduitd over the
   resident Unix socket (`~/.conduit/conduitd.sock`) — it holds nothing across runs except its own
   `NSUserDefaults` preferences and update-check state.
2. **No runtime state is cached as truth in the app.** Anything the app shows that originates from
   conduitd (session list, approval queue, audit tail, secret metadata, policy YAML, pairing
   status) is a transient render of the last IPC response, never persisted by the app as the
   source of truth. A relaunch re-fetches; it never trusts a local copy over conduitd's answer.
3. **Writes to owned state go through versioned IPC calls, never by editing conduitd's files
   directly.** Lancer.app must never write to `~/.conduit/secrets.json`, `~/.conduit/queue.json`,
   `~/.conduit/audit.log`, `~/.conduit/relay-pairing.json`, or any policy file. Every mutation goes
   through the corresponding RPC (`agent.secret.store`, `agent.approval.response`,
   `agent.policy.set`, `conduit.device.register`, etc.) so conduitd remains the sole writer and
   the single point of validation, audit, and fail-closed enforcement.
