# Mac ↔ iOS responsibility matrix

> Defines the product boundary between **Lancer for Mac** (`LancerMac`, the new native
> management/companion app) and the existing iPhone app. The Mac app is a **manager and
> health surface for the Host Service**, not a second place to run agent work. Grounded in
> `ARCHITECTURE.md` §0.1 (current-state snapshot) and §4.1 (the iPhone home is a
> **sidebar/Command Home shell**, not a tab bar) and the plan at
> `.claude/plans/you-are-working-on-curried-pixel.md`.
>
> **Architecture in one line:** `Lancer.app` (Mac) manages the lifecycle of the existing
> `conduitd` Go daemon (the **Host Service**, unchanged) over a hardened local Unix-socket
> IPC. `conduitd` is still the only thing that owns sessions, PTYs, policy, approvals, audit,
> and the relay connection. The iPhone keeps talking to `conduitd` directly (via the E2E
> relay) — **not through Lancer.app.** Quitting Lancer.app never stops agent work.

---

## 1. Lancer for Mac owns

Installer, lifecycle manager, and local health surface for the Host Service. Everything
here is either (a) physically only possible from the machine itself, or (b) a presentation
of host state with no remote/mobile equivalent worth building.

| Area | What Lancer for Mac owns | Why it's Mac-only |
|---|---|---|
| Host Service install | Install / register `conduitd` as a per-user LaunchAgent (`SMAppService`, falling back to the existing plist) | Requires local filesystem + launchd access |
| Host Service update | Update and remove the Host Service binary/LaunchAgent | Local install artifact |
| Launch-at-login | Configure launch-at-login for the Host Service | macOS login-item API, local only |
| Existing-daemon migration | Detect a standalone `conduitd` already installed via CLI and adopt it without clobbering `~/.conduit/` | Migration logic must run on the host with filesystem access |
| Agent discovery | Detect installed coding-agent CLIs (Claude Code, Codex, OpenCode, Kimi) and their versions | Reads local `PATH` / binaries |
| Provider auth health | Surface whether each agent CLI's provider auth (API key / OAuth) is valid | Reads local credential state the CLI manages |
| Workspace roots | Configure the allowed workspace root directories agents may operate in | Local filesystem picker; defines blast radius for *this* machine |
| Machine-local permissions | Set machine-level permission defaults (what an agent can touch without asking) | Applies only to this host's filesystem/policy engine |
| Pairing | Drive `conduitd pair`, render the QR / 6-digit code, show mutual-verification phrase | The daemon already generates the X25519 pairing payload; Mac is the natural place to display a QR for a phone to scan |
| Revoking phones | Revoke a previously paired phone's access | Local control of `conduitd`'s device-binding state |
| Rotating machine identity | Rotate the machine's relay/device identity key | Security-sensitive, host-initiated action |
| Connection health | Show direct-connection and relay connection status for this machine | Local network/process state |
| Connection & push tests | Run "test direct," "test relay," "test push" diagnostics end-to-end | Needs to originate a real round-trip from the host |
| Active-agent glance | Compact, denser view of currently running agents across local sessions | Operational glance for someone sitting at the Mac |
| Attention counts | Badge/count of items needing approval, surfaced in menu bar | Local proxy of `conduitd` state, read-only |
| Pause / stop all (local) | Pause or stop all agents running on *this* machine | Scoped to the local Host Service, not the fleet |
| Machine-level policy defaults | Configure this machine's default autonomy/policy posture (ask/allow/deny defaults) | Per-host policy config, not a per-conversation override |
| Local secrets & credentials | Manage where this machine stores secrets (Keychain), never persisting them in the app itself | Read-through to Keychain/`conduitd`, host-scoped |
| Diagnostics / logs | Run `conduitd doctor`, view logs, export a redacted support bundle | Needs local log/file access |
| App & service updates | Manage Lancer.app's own update state and the Host Service's update path | Local app lifecycle concern |

---

## 2. The iPhone remains primary for

Everything about *doing* and *responding to* agent work — starting it, watching it, and
acting on it — stays on the phone. This is unchanged by Lancer for Mac's arrival.

| Area | Why the iPhone stays primary |
|---|---|
| Starting remote agent work | New Chat (`.newChat` in `ConduitSidebarView`) is the dispatch surface; this is where work begins |
| Durable chat threads | `ChatConversationRepository`-backed threads are the system of record for agent conversations |
| Continuing sessions | Per-vendor `continue`/follow-up (new `runId` per turn) is a mobile-first interaction pattern |
| Approval Inbox | `InboxView` (`.needsAttention`) is the system of record for approvals — full review surface |
| Approve / deny / edit actions | The governed-approval loop (hook → policy → inbox → approve → audit) is decided on the phone |
| Diff review | Reviewing an agent's most recent patch before approving |
| File preview | Inspecting cwd + last-touched files tied to a live session |
| Proof / test review | Reviewing test/proof output attached to a run before signing off |
| Remote terminal | The unified-PTY → `BlockRenderer` live block terminal (machine detail drill-in) |
| Remote machine fleet | `FleetView` — browsing hosts and active session slots (≤3) across the whole fleet, not just the local Mac |
| Push notifications | APNs delivery, Live Activity, lock-screen approve actions |
| Remote emergency stop | Stopping agents on *any* machine in the fleet, not just the one you're sitting at |
| Mobile quota-aware agent selection | Choosing which vendor/agent to dispatch based on live quota state, while away from any machine |
| On-the-go intervention | The entire premise of Conduit/Lancer — steering agents without being at a keyboard |

---

## 3. Shared, but with different presentation

Both surfaces read the *same* underlying state from `conduitd` (or, for fleet-wide items,
from the relay/push-backend) — neither app caches it as its own source of truth. The
difference is density and intent: **Mac is denser, operational, glanceable; iPhone is
actionable, mobile.**

| Shared item | Mac presentation | iPhone presentation |
|---|---|---|
| Machine health | Menu-bar icon + Diagnostics pane: live IPC/relay/direct/push status, each surfaced individually, for *this* machine | `FleetView` host row: a single rolled-up health indicator per machine, swipeable across the fleet |
| Agent state | Dense list of all local sessions/processes with status, cwd, vendor, in one window | Per-machine session slots (≤3) inside Machine Detail, framed as a card the user taps into |
| Provider quota | Compact per-agent-CLI quota readout next to auth health, for agents installed on this Mac | Quota-aware agent picker at New Chat dispatch time — informs which agent to *choose*, not just a readout |
| Paired devices | Devices pane: full list of paired phones with fingerprint, last-seen, revoke action | Settings → Connection → Devices: same data, scoped to managing *this* phone's own binding, simpler list |
| Policy status | Security pane: effective autonomy/policy summary for this machine, with explicit confirms for sensitive changes | Inline risk band on each approval card (§4.5 in `ARCHITECTURE.md`) — policy made concrete at the moment of decision |
| Audit summary | Diagnostics pane: scrollable/exportable audit log, redacted support bundle | Inbox History sheet: recent approvals/decisions, framed as something to review, not export |
| Emergency stop | "Pause/stop all" scoped to the local Host Service, one click, no confirmation theater (you're at the machine) | Remote emergency stop across the fleet, explicit confirm step (you are *not* at the machine, must be certain) |

---

## NOT in the first Mac release

To keep Lancer for Mac a companion, not a clone, the first release explicitly **excludes**:

- **No full transcripts** — no durable chat/conversation reading UI on Mac.
- **No terminal** — no block terminal / PTY rendering on Mac; that stays an iPhone (and legacy SSH) surface.
- **No full approval inbox** — Mac shows attention *counts*, not a review-and-decide inbox.
- **No file browser** — no cwd/file-preview surface on Mac.

These are deliberate scope cuts, not gaps to be filled incrementally inside this release —
see the plan's "Explicitly deferred (YAGNI)" list for the corresponding engineering
scope (`lancerctl`, Sparkle auto-update, Mac terminal/file-browser/full-inbox/transcripts,
Mac App Store/sandbox build).
