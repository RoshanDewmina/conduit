# 09 — Fleet, Activity, and Terminal

> Source: Wave-2 operational-products research (Mobbin + Tailscale/Termius/GitHub-Mobile docs + Apple HIG + repo grounding). Each finding: Observed → Evidence → Interpretation → Lancer rec → Confidence.

## Grounding — Lancer's primitives are already close to best practice

| File | Today | Patterns / gaps |
|---|---|---|
| `FleetView.swift` | Single-machine "board": status header, RELAY/DIRECT chip, banners (local-model, attention, RUNNING NOW), relay machine card, "Agents on this host" rows, stat cards (Usage / Connection / Setup drift), saved-hosts list, Reconnect/Add | Already icon+label+severity (`statusLine`/`statusColor`); header focuses ONE machine (`focusSlot`); status never color-only ✅ |
| `FleetStore.swift` | ≤`maxSlots`; `connectionState(for:)` derives ONE honest state; fleet-wide picks most-live slot; `allPendingApprovals` | **Status model is centralized and testable — the inconsistency bug is a view-binding problem, not a model gap.** |
| `ActivityView.swift` | Two-section feed: "ON THIS PHONE" (local `AuditEvent`) + "CONNECTED HOST" (`BridgeAuditFeedView`); "FULL AUDIT LOG" → `AuditView`; `showsHeader` flag | Rows already icon+color+label+timestamp; no filter/search/grouping/export here yet; provenance split is good |
| `SessionWorkspaceContainer.swift` | Warp-style drawer: Workspace · Files · Diff · Preview over SSH; `RelayWorkspaceUnavailableView` gates terminal/files behind "Connect over SSH" + "Relay still handles dispatch, output, approvals" | **The exact right V1 framing** — keep it |
| `LiveTerminalView.swift` | Raw PTY (dormant escalation), `KeyboardAccessoryRail` with latch-able Ctrl | Special-keys rail + Ctrl-latch already exist (SSH-mode UI) |

## Fleet / devices

**Status model (synthesis — the highest-leverage fix).** Every credible product (Telegram, Chime, Apple/Google Home, Tailscale, Starlink) encodes device status as **`{glyph} {word} · {qualifier/last-seen}`** with color as a non-load-bearing 4th channel. Mandate it as a design primitive `DSMachineStatus`:

| State | Glyph | Word | Color token | Qualifier |
|---|---|---|---|---|
| Connected (SSH) | filled dot, pulse | `online` | `t.ok` | `· direct` |
| Relay-paired | filled dot | `online` | `t.ok` | `· relay` |
| Connecting | spinner | `connecting…` | `t.warn` | — |
| Degraded (drift/quota) | triangle | `attention` | `t.warn` | `· 2 findings` |
| Unreachable | triangle | `unreachable` | `t.danger` | `· tap to reconnect` |
| Offline / saved | hollow dot | `offline` | `t.text3` | `· last seen 5h ago` |
| Busy / running | dot, pulse | `running` | `t.accent` | `· {step}` |

Three concrete deltas vs current code: (a) **add the relative last-seen qualifier** for offline hosts (Chime pattern); (b) **add a `busy/running` per-machine state** distinct from `connected`; (c) **bind header + row + top-bar to the single `connectionState(for:)`** to permanently kill the label-disagreement bug (P0-2 in [03](03-current-ui-audit.md)). **Confidence: High.**

**Machine list vs detail — adaptive.** One machine → the detail *is* the screen (current `FleetView` board, validated by Starlink's "Online" hero + metric tiles). Two+ machines → a compact **switcher list** at top (avatar + name + status + chevron) with the board below; tapping refocuses. Saved/offline hosts in a separate "Saved" group with last-seen. **Don't build Termius-style host grouping/tags at ≤3 slots (YAGNI).** **Confidence: High.**

**RELAY/DIRECT chip** is a capability anchor, not cosmetic (Tailscale surfaces direct-vs-relay as first-class). Tapping it explains "Relay: dispatch + output + approvals. Connect over SSH for terminal/files/preview" — reuse `RelayWorkspaceUnavailableView` copy. Turns a status label into a teachable upgrade path. **Confidence: High.**

## Activity / audit

**Activity is NOT a primary nav root** — it's a contextual drawer/detail reachable from Home/Inbox **and** each Machine's detail (scoped to that host). The repo's `showsHeader` flag already anticipates this; the audit log is *evidence for governance decisions*, not a daily destination.

Row anatomy: **`{glyph} {actor} {action} {target} · {relative time}`** (Discord audit-log structure — actor = agent name / "You" / "Machine"). Use:
- **`DSDiffChips` (X → Y)** for transition events: host-key change (old→new fingerprint, in `t.danger`), approval (`pending → approved`), policy (`ask → auto`) (monday.com pattern).
- **Sticky date headers** (Today / Yesterday / dated) + an explicit retention/scope label ("Last 100 events on this device" — code already loads `limit:100`) (Squarespace pattern).
- **Severity color** for security events (`authFailure`, `hostKeyChanged` in `t.danger` — already done).
- Keep the **ON THIS PHONE / CONNECTED HOST provenance split** (stronger than Squarespace's IP column).
- **The differentiator: link each event back to its originating session/thread** in the detail (an approval audit row → the chat thread where it was decided).
- **Export/verify stays in the deeper `AuditView`** (governance power-action), not the glanceable feed.

Add type + date **filter chips** when volume grows (Google Home Events/Date). **Confidence: High.**

## Terminal / sessions

**The V1 "terminal" should be GitHub-Mobile-shaped, not Termius-shaped.** GitHub Mobile gives glanceable status rows + drill-in to read-only output, not a live shell; in-progress work = a labeled spinner row. That is exactly the relay model (you watch and steer, you don't type into a PTY).

| Scope | V1 (relay, no phone SSH) | Post-V1 (SSH / power-user) |
|---|---|---|
| Surface | Read/scroll **block transcript** (Warp-style cards from BlockRenderer) | Interactive `LiveTerminalView` PTY |
| Input | **Follow-up composer** (new instruction to agent) | Keystroke PTY + `KeyboardAccessoryRail` (Esc/Tab/Ctrl/arrows/`|~/-`) |
| Interrupts | **Approval interrupts + Emergency Stop** | same |
| Per-block actions | **Copy · Send to agent · Expand/collapse** (collapse long output beyond N lines) | + Re-run |
| Files | Browse-only (relay `fsList`) | SFTP + Workspace/Files/Diff/Preview drawer |

V1 is fully achievable over the blind relay (dispatch + output + approvals) and needs no SSH. Keep `RelayWorkspaceUnavailableView` as the honest gate for everything else — its capability framing ("Relay still handles dispatch, output, and approvals") is correct. **Don't dump raw scrollback** (the Google-TV "Log contents" anti-pattern); block cards exist to avoid that. **Confidence: High.**

**Sessions persist as durable chat threads** (the sidebar home), NOT as terminal-tabs. "Switch session" = pick a thread. On reconnect, show a clear connection-state banner in the thread ("Reconnecting…", "Bridge unreachable — tap reconnect"), never dump the user into a dead PTY. **Confidence: High.**

## Primary-nav vs contextual — placement verdicts

| Surface | Placement | Rationale |
|---|---|---|
| **Machines / Fleet** | **Sidebar root** (one of few) | "What am I steering" inventory; ≤1 tap. Adapts: N=1 detail-board, N≥2 switcher list |
| **Machine detail** | Drill-in from Fleet | Depth not breadth; hosts agents, stat tiles, per-machine activity, terminal entry, drift, disconnect |
| **Session / terminal** | Drill-in from thread/machine | Threads ARE the session list (sidebar); terminal is a thread's body |
| **Activity / audit** | Contextual drawer (global + per-machine) | Governance evidence; `showsHeader` anticipates this; export deeper in `AuditView` |
| **Emergency Stop** | Globally reachable + per-session | Safety-critical; never >1 deliberate action away |

## Emergency Stop — a Lancer-specific safety primitive

No surveyed consumer app has a true "kill the running job" control because none carry Lancer's risk (autonomous agents changing your machine). It's a differentiator. Placement:
1. **Per-session Stop** — persistent, always-visible in the session/terminal header while an agent is `running` (red, labeled "Stop", confirms once).
2. **Fleet-wide "Stop all"** — in Machine/Fleet detail + the RUNNING NOW band; one deliberate destructive action to halt every running agent.
3. **From the approval flow** — a "deny + stop" option (deny the action AND halt the run).
4. **NOT a Live-Activity / Lock-Screen button** — HIG disallows interactive Live-Activity buttons; instead the Live Activity / push **deep-links into the in-app Stop** (one tap from notification → session → Stop). **Confidence: High (placement); Medium (daemon wiring, out of lane).**

## Bonus — running-agent Live Activity (post-V1)

A strong glance + differentiator: compact = agent glyph + machine + step; expanded = goal + progress + "pending approval" alert; tap deep-links to the session (→ Stop/approval). HIG constraints: defined begin/end, **≤8 hours** (long runs degrade to a normal push), end immediately on completion, no interactive Lock-Screen buttons. Ship only once relay→push latency is reliably low ("ship the live loop first"). **Confidence: Med-High.**

## Sources

Mobbin: [Telegram devices](https://mobbin.com/screens/26a2393a-80c7-4507-a497-d5908a9f5c81), [Chime my devices](https://mobbin.com/screens/b19183d6-a104-447d-b598-8bfed52ec096), [Starlink status](https://mobbin.com/screens/7765bb6f-a321-44b4-ab64-9196ee1aa8d4), [Apple Home offline](https://mobbin.com/screens/9338c84f-8c3f-4256-bfb2-c7c31515df08), [Discord audit log](https://mobbin.com/screens/97c3615a-5eca-4a3b-a5f5-f2f2a194bcda), [monday.com activity](https://mobbin.com/screens/360b60f2-bc0b-48ea-9b85-202e8f3c3dcb), [Squarespace activity](https://mobbin.com/screens/56ecba1b-7986-4493-a50c-d735a05ed8f4), [GitHub checks](https://mobbin.com/screens/72a822ab-e14b-47a5-a29c-34e9c418296e). Docs: [Tailscale device management](https://tailscale.com/docs/features/access-control/device-management/how-to/filter), [Termius](https://termius.com/index.html), [HIG Live Activities](https://developer.apple.com/design/human-interface-guidelines/live-activities/).
