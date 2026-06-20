# Conduit — Architecture & Product Specification

> *Phone-native cockpit for remote AI coding workspaces.*

Last updated: 2026-06-20 (editorial Command Home redesign and workspace refresh)
Target platform: iOS 27.0+ deployment (project.yml and Package.swift); verified with Xcode 27 / iOS 27 simulator (Swift 6.2, strict concurrency on)
Status: M1–M10 complete on master; M11 (temporal wall / unified PTY) Phase 0–1 + UX in progress

---

## 0. Document scope

This is the single source of truth for what Conduit is, why it exists, what it
will and will not do, and how it is built. It is structured to be cited from
code reviews, design reviews, and roadmap discussions. When code disagrees
with this document, one of the two is wrong; do not let drift accumulate.

The document is intentionally opinionated. Where multiple viable approaches
exist, the chosen approach is named and the alternatives are recorded with
the reason for rejection.

---

## 0.1 Current state snapshot (authoritative — 2026-06-19)

> A new agent should be able to read **this section + §4.1** and know where the project
> stands without opening any other doc. Where older sections below conflict with this
> snapshot, **this snapshot wins** until they are rewritten. The former
> `docs/CONDUIT_PROJECT_DOSSIER.md` is **archived** (`docs/_archive/`); this is its successor.

**What Conduit is:** an iOS "mission control" for AI coding agents (Claude Code, Codex,
OpenCode, Kimi) that run on the developer's own machines/servers. The phone steers and
approves; it is not where code is written. Three fused layers:
1. **iOS app** — `Packages/ConduitKit/` (SwiftUI, 21 SPM targets). **Sidebar / Command Home shell** (see §4.1).
2. **`conduitd`** — Go resident daemon on the dev's host: policy/approval/audit/dispatch, survives SSH drops. `daemon/conduitd/`.
3. **`push-backend`** + **`agent-runner`** — Go hosted-cloud control plane (Stripe credits, quotas, multi-cloud run dispatch). `daemon/push-backend/`, `daemon/agent-runner/`. **Deferred to V2** (see scope below). Note: `push-backend` **also hosts the APNs relay** used by V1 — only the *hosted-execution* product is deferred, not the push relay.

**V1 transport = the blind E2E relay.** The phone (`E2ERelayClient` + `E2ERelayBridge`) pairs to
the `push-backend` relay, and the resident `conduitd` connects to the same relay on the host side;
phone ↔ **relay** ↔ daemon. The relay is end-to-end encrypted — it forwards ciphertext it can't read.
**The phone never holds an SSH session in V1.** A second transport — SSH (`conduitd serve` over a live
session, `DaemonChannel`) — still exists in code but is **legacy / power-user, NOT the V1 path**; do
not frame V1 around it. Both transports re-run policy + budget gates.

> **Resilience implication:** because the **resident daemon** holds session/approval state and the phone
> only attaches via the relay (waking on APNs), "the agent survives when the phone disconnects" is a
> property of the architecture, not a feature to add. This is why Mosh-style roaming transport (Moshi)
> and cloud session-migration (Omnara) are largely **non-gaps** for Conduit — the phone was never the
> session holder.

### V1 scope (locked 2026-06-18; transport corrected 2026-06-19)
- **V1 ships:** the sidebar/Command Home shell, the **E2E-relay transport** (SSH is legacy/secondary, not the V1 story), governed approvals (hook→policy→inbox→approve→audit), APNs notifications, machine detail (≤3 live sessions), and **multi-vendor dispatch *with `continue`/follow-up*** for Claude/Codex/OpenCode/Kimi.
- **Deferred to V2 — code is RETAINED, not deleted:** the **hosted-cloud execution** product (run agents on Fly/GCP/Lightsail, prepaid credits, the `Provider*/Hosted*/SelfHostVsHosted` UI). It compiles and stays in tree; it is simply **not wired into V1 navigation**. Do not delete this code. The relay-first / self-host positioning is the V1 lead bet; hosted-cloud is the V2 expansion.

### Implemented (✅ verified in code / tests)
- **Sidebar/Command Home IA** with durable chat persistence (`ChatConversationRepository`), thread resume, inline tool-call/artifact cards, follow-up continuation (new `runId` per turn).
- **SSH + block terminal:** TOFU, Ed25519/password, unified PTY → OSC-133/7 → `BlockRenderer`, alt-screen TUIs in-block, auto-reconnect + tmux resume, GRDB persistence.
- **conduitd:** policy engine (deny>ask>allow, fail-closed default ask), audit log, allow-always persistence, blast radius, offline queue, dispatch + schedules, push POST; per-vendor argv for Claude/Codex/OpenCode/Kimi incl. continue/resume.
- **push-backend:** Stripe billing + prepaid credits + overage/402, quotas, orgs, schedules + cron, artifacts, run-logs, dispatch spine + per-run scoped runner tokens.
- **Cross-cutting:** APNs models + relay POST, Live Activity, Watch app/widgets, biometric gate + app-lock + audit redaction, relay key in Keychain, StoreKit lifetime IAP, onboarding redesign, fleet (≤3 slots), emergency stop.
- **V1 reach work (2026-06-19, code-complete; device verification pending):**
  - **opencode approval gating** — conduitd-dispatched `opencode` runs now gate every tool call through the policy engine via a `CONDUIT_GATE=1`-guarded PreToolUse hook (the guard means the owner's interactive opencode sessions are unaffected). Live-verified against `~/.conduit/audit.log` (auto-allow + auto-deny, hash-chain intact). Closes the prior governance bypass where only Claude Code gated. `daemon/conduitd/dispatch.go` + `docs/opencode-conduit-hook.sh`.
  - **Push-driven Live Activity** — `LiveActivityManager` requests `pushType: .token`, streams `pushTokenUpdates` + `pushToStartTokenUpdates`, so the lock-screen / Dynamic Island update **while the app is closed** (was local-update-only → stale when backgrounded). New `daemon/push-backend/liveactivity.go` ActivityKit sender with the strict APNs contract (`<bundle>.push-type.liveactivity` topic, pinned `Date` encoding). **APNs payload privacy:** the alert body no longer carries the raw command (`body := ev.Command` removed) — redacted risk/tool summary only; full detail fetched in-app post-unlock.
  - **Cold-decision gate** — `ApprovalRelay` hydrates relay credentials from Keychain at decision time so an Approve tapped from a killed-app Live Activity forwards to conduitd (previously the singleton creds were empty cold → decision dropped).
  - **Watch WCSession polish** — `PhoneWatchConnector` pushes live `agentActive`/`pendingCount`/uptime (were hardcoded stubs); `InboxCountWidget` gains `.accessoryRectangular` + VoiceOver labels.

### Partial / built-but-not-wired (🔶)
- **Chat artifacts:** `ChatArtifactCard`/`ChatArtifactDetailView` (6 sub-cards, 14 tests) are the **intended richer artifact renderer** but are **not yet wired** — `NewChatTabView` currently renders live tool calls via its own `InlineChatToolCard`. **Decision (2026-06-18): keep both**; they are complementary (live tool-call card vs. run-artifact card), not duplicates. Wire `ChatArtifactCard` when run artifacts (diff/file/test/preview) flow into the transcript. `FleetThreadMapper` (4 tests) similarly built, awaiting fleet→thread wiring.
- **Structured tool_use richness** (full typed input end-to-end), **org email delivery**, **live APNs device delivery** — not yet proven on device (see `docs/LIVE_LOOP_RUNBOOK.md`). The Live Activity **push token → push-backend registration** now routes securely through `DaemonChannel.registerActivityToken` → conduitd RPC `conduit.device.register.activity` → push-backend (conduitd holds `APPROVAL_RELAY_SECRET`; the app never does). **One manual wiring step remains:** paste the `.conduitLiveActivityTokenReady` subscriber into `AppRoot.configureE2ERelayBridge` (next to the `.conduitAPNSTokenReceived` one) and call `startPushToStartMonitor(sessionID:)` — deferred only because `AppRoot.swift` is under active IA editing.
- **`continue`/follow-up:** implemented for all vendors in `dispatch.go` (`continueArgv`) — **in V1 scope.** Re-verify each vendor's argv with the `vendor-cli-adapter-audit` skill before trusting (CLI flags drift).

### Deferred to V2 — code retained, NOT deleted
- **Hosted-cloud execution UI:** `ProviderDetailView`, `HostedProvisioningView`, `HostedRunnerStatusView`, `SelfHostVsHostedView` (orphaned, 0 refs) and the `agent-runner`/multi-cloud dispatch depth (Fly real; GCP needs an image; Lightsail bootstrap only). Compiles, stays in tree, unwired in V1. **Do not delete.**

### Planned (not started)
- First-class **Loop** primitive (`conduit_loop_start`/`conduit_step_complete`) per the "control plane for loops" thesis — backend has no Loop object yet.
- Cross-vendor breadth beyond the four CLIs; open-sourcing `conduitd`.

### Deprecated / removed
- **Tab-bar IA** (`Inbox/Fleet/Activity/Settings`, `…/Control/…`) — replaced by the sidebar shell (§4.1).
- Deleted dead files (2026-06-18): `ControlView.swift` (old Control tab), `AdaptiveRoot.swift`, `LibrarySupportViews.swift` (`KeysManagementView`, superseded by `KeysFeature`). Earlier: `PreviewFeature`, `SnippetEditorView`, zero-ref design-system atoms.
- `docs/current-state-audit.md`, `docs/remaining-work.md`, `APP_AUDIT.md`, `cloud-execution-engine-plan.md`, `CONDUIT_PROJECT_DOSSIER.md` → `docs/_archive/` (point-in-time, superseded).

### Current priorities (in order)
1. **Close the live loop on a real device:** hook→policy→inbox→approve→audit + **APNs delivery while the app is closed** + relay dispatch round-trip, end-to-end (the #1 unverified gap). Step-by-step: **`docs/LIVE_LOOP_RUNBOOK.md`**.
2. **App Store Connect setup + TestFlight** (the main external ship gate).
3. Optional V1 polish: wire `ChatArtifactCard` + `FleetThreadMapper`; empty/error/a11y sweep; pixel polish.

---

## 1. Product thesis

**Phones are not where serious software is written. They are where serious
software is steered.** Conduit is built around that asymmetry.

Concretely: the iPhone (and iPad) is the best on-body computer humans have
ever owned. It is always with the developer, has push, biometrics, camera,
GPS, a good keyboard for short bursts, and durable cellular. What it is bad
at is hours of dense keyboard work on a small screen. The remote workspace —
a cloud VM, a personal devbox, a teammate's machine, or a self-hosted server
— is where the toolchain, the repo, the AI agent, the language server, the
test runner, and the dev server actually live.

Conduit is the missing client. It is not a phone IDE. It is the **control
plane for remote AI coding**, optimized for six jobs the research validates
as the actual mobile loop:

1. **Attach** to a remote workspace in under three seconds.
2. **Survive** network handoffs (Wi-Fi ↔ cellular ↔ elevator dead zones).
3. **Notify and approve** agent actions without context-switching apps.
4. **Review** diffs, logs, and test output on a phone-sized screen.
5. **Transfer** screenshots, files, and snippets into prompts in one tap.
6. **Preview** the running app's UI without reaching for a laptop.

Anything that does not directly serve one of these six jobs is deferred.

### 1.1 Non-goals

These are explicit non-goals, not "later" features. We will not pursue them
even when users ask, because pursuing them dilutes the product.

| Non-goal | Why we will not do it |
|---|---|
| **Local iOS code editor** | iOS sandbox blocks the toolchains worth editing for. Code App's documented limits show the ceiling. The remote machine already has a real editor. |
| **Local language servers / build tools** | Same reason. iOS will not host useful clangd, gopls, rust-analyzer, or modern Node. Path to obsolescence is short. |
| **Full desktop split-pane layouts on the phone** | Density on a 6.1" screen produces tap-targets too small to hit reliably. Use stacked sheets and quick transitions. iPad gets real splits. |
| **Custom SSH protocol implementation** | swift-nio-ssh + Citadel is solved. Re-implementing SSH is a multi-year tax with no upside. |
| **Built-in cloud VMs at launch** | The cost envelope (see §13) destroys margins. Start BYO-host / BYOK. Managed compute is a later, opt-in upsell. |
| **Generic "mobile terminal" positioning** | Termius and Blink already own that frame. Conduit's wedge is *AI workflow*, not raw terminal. |
| **Pure subscription gating of the client** | Documented backlash against Blink/Termius pricing makes this commercially bad. Client is paid; cloud and AI are metered. |
| **Re-implementing tmux semantics in-app** | Server-side `tmux` is universal, durable, and our users already know it. We integrate, we do not replace. |
| **Real-time multi-cursor collaboration** | Wrong product. We are async / steering, not pair-coding. |

---

## 2. Naming, identity, and scope

- **Name:** Conduit
- **Bundle ID:** `dev.conduit.mobile` (app), `dev.conduit.kit` (frameworks)
- **Platforms:** iOS 27.0+ / iPadOS 27.0+ deployment target, tested on the iOS 27 simulator. watchOS 26.0+ for the companion Watch app. macOS Catalyst deferred.
- **Toolchain:** Xcode 27.x, Swift 6.2, SwiftPM-first. Strict concurrency and existential-any are defaults — no upcoming-feature flags needed.
- **License:** TBD. Engine modules (TerminalEngine, SSHTransport) likely
  open under MIT/Apache-2.0; feature modules and the app stay proprietary.

---

## 3. Competitive landscape

### 3.1 Direct competitors

| Product | Class | Mobile? | AI-native? | Wedge against us |
|---|---|---|---|---|
| **Termius** | SSH client | iOS + Android + desktop | Bolted on (AI in terminal) | Mature, 18K+ iOS ratings @ 4.7, mature SFTP. Weak: no agent-first inbox, subscription pain, no diff/preview surface, AI is a sidecar. |
| **Blink Shell** | SSH/Mosh client | iOS only | No | Best raw mobile terminal UX (Mosh, hardware kb, external display). Weak: subscription resentment, no agent loop, no structured inbox. |
| **Helm** *(internal predecessor)* | Agent supervision shell | iOS | Yes, Claude-only | Strong pairing/crypto and chat. Weak: requires desktop helper, single-host model, no general SSH terminal. |
| **Nimbalyst** | AI coding companion app | iOS | Yes | Kanban + diffs + multi-agent. Weak: review-only, no real terminal. |
| **Claude iOS app (Claude Code)** | Anthropic's official | iOS | Yes, Claude-only | Native push + approve. Weak: locked to Anthropic, no shell, no other agents. |
| **OpenAI Codex mobile** | Web wrapper | iOS PWA | Yes, Codex-only | Phone monitors remote runs. Weak: not a terminal, locked to OpenAI. |
| **Code App** | Mobile IDE | iOS | No | Best local-IDE attempt on iOS. Weak: iOS sandbox limits, no agent layer. |
| **Termux** | Local shell | Android | No | Vast local toolchain. Weak: Android-only, Android 12+ phantom-process kills break long agent runs. |

### 3.2 Desktop benchmarks (architecture/UX reference, not competitors)

| Product | What we steal | What we ignore |
|---|---|---|
| **Warp** | Block-based terminal model; AI Command Search; Workflows; Drive concept | Desktop pane density; Rust client weight |
| **cmux** | Remote daemon w/ proxy stream RPC; HMAC-authenticated relay; SHA-256-verified daemon upload; smallest-screen-wins PTY resize; reverse-TCP CLI relay; per-workspace browser proxy via SOCKS over RPC | macOS-only window management; AppKit splits |
| **Ghostty** | libghostty terminal correctness; standards-compliant VT/xterm; GPU rendering ambition | Desktop-only window/tab UI |
| **Tabby** | Plugin model; tab/split semantics | Electron weight |

### 3.3 Where competitors fail and we should win

Drawn directly from issue trackers, App Store reviews, and the research report:

1. **Background / network handoff drops** — universally documented complaint.
   We solve it with `tmux`/`screen` first-class, Mosh transport, and a Network
   framework reachability + reconnect engine that survives Wi-Fi ↔ cellular.

2. **Touch keyboard insufficient for terminal work** — Termius is the only
   one that took this seriously. We adopt Termius's gesture playbook (long-press
   space for arrows, three speed gears, customizable extra-key rail) and add
   *AI command synthesis* in the same input bar (`#` prefix).

3. **External keyboard is fragile** — Blink and Termius both have open
   issues. We design for hardware-keyboard parity from day one
   (`UIKeyCommand`, focus system, modifier-flag round-trip to PTY).

4. **No first-class agent inbox** — every product treats agent notifications as
   a sidecar. We make the **Inbox** a top-level tab equivalent to Terminal.

5. **File/screenshot transfer into prompts is clumsy** — we make the Share
   Sheet, Photos picker, and Files picker first-class composers, with one-tap
   "attach to active prompt".

6. **Preview is missing or fragile** — Helm proved curl-over-SSH preview works.
   We extend it to SOCKS-over-stream-RPC (cmux's model) for proper websockets
   and live reload.

7. **Subscription resentment** — we sell *client UX* once and meter *AI* and
   *cloud compute* separately. BYO host + BYOK is free forever.

### 3.4 Feature matrix

Legend: ✅ first-class · 🟡 supported · ⚪ not supported · 🔒 paid tier · ⏳ roadmap

| Capability | Termius | Blink | Warp (desktop) | cmux (mac) | Helm | **Conduit** |
|---|---|---|---|---|---|---|
| SSH (password, key, agent) | ✅ | ✅ | ✅ | ✅ | ⚪ | ✅ |
| Mosh | ✅ | ✅ | ⚪ | ⚪ | ⚪ | ⏳ M3 |
| Ed25519 in Secure Enclave | 🟡 | 🟡 | ⚪ | ⚪ | ⚪ | ✅ |
| Block-based terminal | ⚪ | ⚪ | ✅ | 🟡 | ⚪ | ✅ |
| Raw PTY (vim, htop, tmux) | ✅ | ✅ | ✅ | ✅ | ⚪ | ✅ |
| Agent inbox / approvals | ⚪ | ⚪ | 🟡 | ✅ | ✅ | ✅ |
| Diff review on phone | ⚪ | ⚪ | ✅ | 🟡 | ✅ | ✅ |
| Live web preview of remote port | ⚪ | ⚪ | ⚪ | ✅ | 🟡 | ✅ |
| Reverse SSH port forwarding (`tcpip-forward`) | ✅ | ✅ | ✅ | 🟡 | ⚪ | ⚪ (known gap) |
| Push notifications | 🟡 | ⚪ | ⚪ | ⚪ | ⏳ | ✅ |
| AI command synthesis (NL → cmd) | 🟡 🔒 | ⚪ | ✅ | 🟡 | ⚪ | ✅ |
| Error-explain on stderr | ⚪ | ⚪ | ✅ | 🟡 | ⚪ | ✅ |
| BYOK Anthropic / OpenAI / xAI | ⚪ | ⚪ | ✅ | ✅ | ✅ | ✅ |
| Cross-device session sync | ✅ 🔒 | 🟡 | 🟡 | 🟡 | ⚪ | ⏳ M5 |
| Hardware keyboard parity | 🟡 | ✅ | ✅ | ✅ | ⚪ | ✅ |
| Snippets / workflows | ✅ | 🟡 | ✅ | ✅ | ⚪ | ✅ |
| Multi-host / multi-session | ✅ | ✅ | ✅ | ✅ | ⚪ | ✅ |
| Live Activities for runs | ⚪ | ⚪ | ⚪ | ⚪ | ⏳ | ✅ |
| iPad split view | ✅ | ✅ | n/a | n/a | 🟡 | ✅ |
| Free tier (BYO host) | ✅ | 🟡 | ✅ | ✅ | n/a | ✅ |
| No-subscription path | 🟡 | ⚪ | ✅ | ✅ | n/a | ✅ |

---

## 4. UX architecture

### 4.1 Top-level navigation — **sidebar / Command Home shell** (redesigned 2026-06-20)

The home is **not** a tab bar. It is a **sidebar/drawer shell** (ChatGPT/Claude-app
style) whose default surface is **Command Home**. Source of truth:
`AppFeature/AppRoot.swift` (`compactRoot` = drawer overlay on iPhone, `regularRoot`
= `NavigationSplitView` on iPad), `ConduitSidebarView.swift`, `SidebarShellState.swift`.

Navigation is driven by `SidebarDestination`, not `enum Tab`:

| Sidebar destination | Surface | Notes |
|---|---|---|
| **Home** (`.home`) | `ConduitHomeView` — attention, machines, recent work | **Default first surface.** Opens New Chat from its primary action. |
| **New Chat** (`.newChat`) | `NewChatTabView` — dispatch + live run transcript | Durable, backed by `ChatConversationRepository`. |
| **Thread** (`.thread(id)`) | `NewChatTabView(initialConversationID:)` | Resume a persisted conversation from the sidebar's Recent list. |
| **Needs Attention** (`.needsAttention`) | `InboxView` (approvals) | Inbox is the system of record for approvals; History/Activity is a sheet off Inbox, not a root. |
| **Machines** (`.machines`) | `FleetView` — hosts + active session slots (≤3) | Machine detail opens a slot's live block terminal as an intentional drill-in. |
| **Settings** (`.settings`) | `SettingsWithLibraryView` | Connection / Notifications / Security / Advanced / Account. |

> **Deprecated:** the earlier `enum Tab { inbox, fleet, newchat, settings }` **tab bar**
> and the `Inbox / Fleet / Activity / Settings` and `Inbox / Fleet / Control / Settings`
> layouts. The `Tab` enum still exists in `AppRoot.swift` but is **vestigial** — only
> `rootDestination(.inbox)` is reached, from inside `sidebarDetail`. `Activity` and
> `Control` are **not** root surfaces; Activity history lives in Recent Threads / the Inbox
> History sheet / audit detail. Do **not** reintroduce a tab bar.
>
> The chat-based session/terminal surface is a **depth** destination reached from
> Machines/Inbox, never a root.

### 4.2 Session screen layout

The Session screen is one vertically-stacked surface. There are no
side-by-side panes on phone. Top to bottom:

```
┌────────────────────────────────────────┐
│  ▸ host  ▸ cwd                ●live   │  ← thin status header (taps for sheet)
├────────────────────────────────────────┤
│                                        │
│  block 0  (last)                       │
│  block 1                               │
│  block 2  (streaming)                  │  ← LazyVStack of blocks
│  ...                                   │
│                                        │
├────────────────────────────────────────┤
│  [tab strip — terminal | diff | files | preview | inbox]
├────────────────────────────────────────┤
│  ⎌  preset row  ⌃ Ctrl-C/D/Z ↑↓←→ ... │  ← KeyboardAccessoryView
└────────────────────────────────────────┘
```

The tab strip switches the upper content area between five linked surfaces
that all share the *same SSH session and cwd*: terminal blocks, diff (most
recent agent patch), files (cwd + last touched), preview (auto-detected dev
server port), inbox (filtered to this session).

### 4.3 Input model

The active block owns input:

- **Prompt state** (after OSC 133 A, before OSC 133 C): typing edits the
  active block prompt. `↩` sends the buffered command to the PTY. `#` prefix
  still invokes NL→command synthesis and inserts the generated shell command
  back into the prompt.
- **Executing state** (after OSC 133 C, before OSC 133 D): the prompt becomes
  a live input receiver. Keystrokes go straight to the PTY, so inline TUIs
  and REPLs can accept repeated input without creating new blocks.
- **Alt-screen state** (`\e[?1049h/l`): SwiftTerm renders the full-screen TUI
  path, with the same PTY and keyboard rail. The desired end state is an
  embedded active-block overlay; current implementation still uses the raw
  SwiftTerm branch.

### 4.4 Keyboard accessory rail

The most important UI element. Built on `inputAccessoryViewController` so it
stays glued to the keyboard during scroll and focus changes.

Preset row (horizontal scroll, customizable, persisted per host):

```
[Bash] [Vim] [Git] [Custom...]    ⌃ ⎋ Tab Ctrl-C Ctrl-D Ctrl-Z ↑ ↓ ← → | ; / $ &&
```

Sticky `Ctrl` modifier (single-tap arms; arms-and-fires next keystroke as
control character then disarms). Long-press a key for repeat. Two-finger
pan on terminal sends `PgUp`/`PgDn`. Long-press space + drag = arrow keys
with three speed gears (Termius pattern, public-domain UX idiom).

### 4.5 Approval inbox card

```
┌──────────────────────────────────────────┐
│ ⚠ Permission needed  ·  myhost · 12:42pm │
│ Claude wants to run:                     │
│ ┌────────────────────────────────────┐   │
│ │ rm -rf node_modules && pnpm i      │   │
│ └────────────────────────────────────┘   │
│ cwd: ~/app/web   ·  risk: medium         │
│                                          │
│ [Allow once] [Allow always] [Reject]     │
└──────────────────────────────────────────┘
```

Risk band is computed locally (see §10) so the user is never lied to about
the criticality.

### 4.6 Diff review

Vertical-only diff renderer. File list at top with `+/-` summary, optional
"only changed hunks" toggle. Inline syntax highlight via TreeSitter (Swift
binding `SwiftTreeSitter`). Each hunk has its own approve/reject — partial
patch approval is supported.

### 4.7 Discoverability heuristics

- First launch: a one-screen explainer of the four jobs, then "Add host".
- Empty terminal: shows the three sample commands and the `#` prompt syntax.
- Long-press anything mono-spaced: contextual menu with copy / send to AI /
  pin as snippet.
- Settings has a "What's new" with each release's new affordance.

---

## 5. Module / package architecture

Conduit is a SwiftPM workspace with a single app target consuming many small
library modules. Modules form a dependency DAG; cycles fail the build.

```
App target  ──────────────────────────────────────────────────────────┐
   │                                                                  │
   ▼                                                                  │
AppFeature (root router, deep links, scene phase, push handler)      │
   │                                                                  │
   ├── WorkspacesFeature ── PersistenceKit                             │
   ├── SessionFeature    ── TerminalEngine, SSHTransport, AgentKit    │
   ├── InboxFeature      ── AgentKit, NotificationsKit                │
   ├── DiffFeature       ── DiffKit                                    │
   ├── PreviewFeature    ── PreviewKit (SSH proxy URL handler)        │
   ├── FilesFeature      ── SSHTransport (SFTP)                       │
   ├── KeysFeature       ── SecurityKit                                │
   ├── OnboardingFeature ── SecurityKit, PersistenceKit               │
   └── SettingsFeature   ── PersistenceKit, AgentKit                  │
                                                                       │
   Engines (no UIKit/SwiftUI imports):                                 │
   ├── ConduitCore       — value types, errors, ids, durations        │
   ├── SecurityKit       — Keychain, Secure Enclave, pairing crypto   │
   ├── SSHTransport      — Citadel wrapper, SessionPool, PTY, SFTP    │
   ├── TerminalEngine    — SwiftTerm bridge, AnsiSGRParser, BlockModel│
   ├── AgentKit          — AIClient, Anthropic, OpenAI, ToolCall      │
   ├── PreviewKit        — SOCKS-over-stream WKWebView proxy          │
   ├── NotificationsKit  — UNUserNotificationCenter, Live Activities  │
   ├── PersistenceKit    — GRDB stack, migrations, repos              │
   ├── DiffKit           — unified diff parser, hunk model, TreeSitter│
   ├── SyncKit           — CloudKit container, CRDT for snippets      │ (later)
   └── DesignSystem      — typography, colors, haptics, icons         │
```

Strict rules:

1. **Engines never import UIKit or SwiftUI.** They are SwiftPM libraries
   testable on macOS CLI. This protects testability and forces a clean
   separation.
2. **Features may import engines and DesignSystem, but never each other.**
   Cross-feature navigation goes through `AppFeature`'s router.
3. **AppFeature is the only place with `@main`.** Even previews go through
   feature-owned preview providers.
4. **All async APIs are `Sendable` and use structured concurrency.** No
   `DispatchQueue` outside the rendering hot path.
5. **Strict-concurrency on, complete-concurrency-checking warnings = errors.**

---

## 6. Technical architecture

### 6.1 Runtime topology

Conduit operates in three runtime tiers; each tier owns specific state and
trust boundaries.

```
┌────────────────────────────────┐
│  Mobile client (iOS / iPadOS)  │
│   - SwiftUI surfaces           │
│   - SSHTransport (Citadel)     │
│   - TerminalEngine (SwiftTerm) │
│   - Secure Enclave keys        │
│   - APNs token / Live Activity │
└────────────────────────────────┘
          │
          │   ① direct SSH/Mosh (default)        ③ APNs push
          │   ② WebSocket control side-channel   (control plane → device)
          ▼
┌────────────────────────────────┐         ┌────────────────────────────┐
│  Workspace host                │         │  Control plane (cloud, opt) │
│   - sshd                       │◀───────▶│   - device registry         │
│   - tmux / screen              │   ④     │   - notification dispatcher │
│   - agent CLIs                 │         │   - audit log               │
│     (claude, codex, opencode)  │         │   - BYOK key passthrough    │
│   - dev server                 │         │   - relay (TURN-style) for  │
│   - git, tests, LSP            │         │     NAT-traversed hosts     │
└────────────────────────────────┘         └────────────────────────────┘
```

Tier 1, the **client**, is the only place private keys live. The Secure
Enclave holds Ed25519 keys when the device supports it; raw key material is
mirrored in the Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`)
for older hardware.

Tier 2, the **workspace host**, runs whatever the user already runs.
Conduit ships an optional, single-binary, code-signed **bootstrap helper**
(`conduitd`) that is uploaded over the SSH session itself, verified against
a SHA-256 manifest embedded in the app bundle (cmux's model), and exposes a
small stdio JSON-RPC surface for: PTY allocation, structured event taps,
SOCKS5 proxy stream RPC, file deltas, and tmux/screen session enumeration.
The helper is *opt-in*; Conduit works fully against an unmodified sshd.

Tier 3, the **control plane**, is intentionally small. It exists only for
the features that *require* a server: push notification dispatch, optional
relay for NAT-traversed hosts, BYO-cloud-account-driven managed compute.
**The control plane never sees plaintext code, prompts, or credentials.**
BYOK API keys are device-resident and used only by the client.

### 6.2 Concurrency model

- **One `@MainActor` UI tree.** Views observe `@Observable` models.
- **Each SSH session is an `actor`** (SSHSession). Per-host concurrency is
  serialized inside the actor; the UI sees one channel of `AsyncStream`
  events per session.
- **Engines surface `AsyncSequence`s only.** Callbacks are not allowed in
  the public API; they hurt structured concurrency.
- **Cancellation is honored everywhere.** Every long-running call respects
  `Task.checkCancellation()`. SSE streams unsubscribe on task cancel.
- **No detached tasks** except in the App scene-lifecycle plumbing where
  the parent task is genuinely the app process.

### 6.3 Lifecycle

```
launch
  ├── load app database (GRDB) on background queue
  ├── restore session registry (no network)
  ├── show Workspaces with offline state
  └── if any host is `autoReconnect`:
      └── start ReconnectEngine
          └── attempt connect with exponential backoff
              ↳ on success: refresh tmux session list,
                            replay scrollback snapshot from server,
                            reattach blocks
```

Backgrounding does **not** drop sessions immediately. We rely on:

- `UIApplication.beginBackgroundTask` for graceful cleanup (~30s).
- Server-side `tmux` for true durability — the client reattaches on resume.
- For paid users, the optional relay proxies keepalives during sleep so
  Mosh-equivalent UX is possible without server changes.

---

## 7. Networking architecture

### 7.1 Transports

| Transport | Use | Library | Status |
|---|---|---|---|
| **SSH (TCP)** | Default execution channel | [orlandos-nl/Citadel](https://github.com/orlandos-nl/Citadel) on swift-nio-ssh | M1 |
| **SFTP (over SSH)** | File transfer, image upload | Citadel SFTPClient | M2 |
| **WebSocket (TLS)** | Control plane: push tokens, relay signaling, sync | `URLSessionWebSocketTask` | M3 |
| **HTTPS (TLS)** | AI provider API, host metadata, manifest fetch | `URLSession` + async-bytes | M1 |
| **SOCKS5 over stream RPC** | Browser preview egress through remote net | `Network.framework` listener + `conduitd` | M4 |
| **Mosh (UDP)** | High-latency cellular durability | `mosh-client` ported to SwiftPM (eval) | M5 |
| **APNs** | Foreground/background approval pushes | `UNUserNotificationCenter` + Live Activities | M3 |

We avoid:

- **Custom binary terminal protocols.** They lock users in and break agent
  CLIs that assume sshd.
- **DataLake / WebRTC** for terminal data. Adds JS/SDP weight; SSH is fine.

### 7.2 Reconnect engine

A single `ReconnectController` actor watches `NWPathMonitor` and the SSH
session state. Rules:

- On `pathUpdate(.unsatisfied)`: mark sessions `.suspended` (UI dims, input
  buffered for up to 10 lines).
- On `pathUpdate(.satisfied)` after `.unsatisfied`: schedule reconnect with
  exponential backoff (250 ms, 500 ms, 1 s, 2 s, 5 s, 10 s capped, jitter).
- On `scenePhase → .background`: keep sessions alive for `min(30s, beginBackgroundTask budget)`.
- On `scenePhase → .active` after a drop: reconnect immediately, replay last
  N bytes of scrollback from server-side `tmux capture-pane`.

### 7.3 Side-channel JSON-RPC

When `conduitd` is installed on the workspace host, we open one additional
SSH `exec` channel running `conduitd serve --stdio`. The protocol is
length-prefixed JSON (4-byte big-endian length, then UTF-8 JSON body), with
JSON-RPC 2.0 semantics and named methods:

| Method | Purpose |
|---|---|
| `session.attach { name }` | Attach to (or create) a tmux session |
| `session.resize { cols, rows }` | Smallest-screen-wins resize (cmux model) |
| `session.detach { name }` | Detach without killing |
| `proxy.open { host, port }` | Open SOCKS stream → returns id |
| `proxy.write { id, bytes }` | Send to stream |
| `proxy.subscribe { id }` | Server-push read events |
| `files.list { path }` | Fast SFTP-equivalent listing |
| `git.status {}` | Cheap git status snapshot |
| `agent.snapshot {}` | Pull pending approvals from local hook DB |
| `hello { protocolVersion, clientVersion }` | Capability negotiation |

This protocol is small, additive, and humans can curl it. We will not let
it grow without explicit review.

### 7.4 Manifest-verified bootstrap

Borrowed directly from cmux. The app bundle ships a `ConduitDaemonManifest`
plist:

```xml
<dict>
  <key>version</key><string>1.4.2</string>
  <key>assets</key>
  <array>
    <dict>
      <key>os</key><string>linux</string>
      <key>arch</key><string>amd64</string>
      <key>url</key><string>https://releases.conduit.dev/d/1.4.2/conduitd-linux-amd64</string>
      <key>sha256</key><string>9f3a…</string>
    </dict>
    <!-- darwin, linux × amd64, arm64 -->
  </array>
</dict>
```

On first attach to a host, Conduit `uname -sm`'s, downloads the matching
asset to `~/.conduit/bin/conduitd-1.4.2`, verifies its SHA-256 against the
bundled manifest, and only then launches it. Updates are pinned to the
shipped app version — never auto-pulled from the network. This is
non-negotiable: the helper runs as the user on their server.

---

## 8. Terminal rendering

### 8.1 Two rendering modes

Conduit operates in two modes, chosen automatically per command:

1. **Block mode (default).** Each shell command produces a discrete `Block`
   object (command + cwd + chunks of stdout/stderr + exit). Streamed in
   real time, scrollable, copyable, re-runnable, AI-explainable. Inspired
   by Warp.

2. **Raw PTY mode.** When the running program enters the alternate screen
   buffer (`\x1b[?1049h`) or we detect a TUI program (vim, htop, less, tmux,
   nvim, fzf, btop, k9s), we hand the channel to `SwiftTerm`'s `TerminalView`
   for full xterm/VT100 fidelity. On exit (`\x1b[?1049l`), we snapshot the
   last frame, fold it into a synthetic Block, and return to Block mode.

The mode transition is invisible to the user beyond the keyboard rail
swapping presets.

### 8.2 Block mode internals

```
SSHTransport.execute(cmd)  →  AsyncThrowingStream<(Data, Stream)>
       │
       ▼
TerminalEngine.BlockRenderer (actor)
       │ on data chunk:
       │   1. utf8 decode (fallback isoLatin1)
       │   2. AnsiSGRParser → AttributedString
       │   3. append to current Block.chunks
       │   4. publish single-line @Observable mutation
       │ on finish:
       │   1. fetch exit code (`echo $?` short channel)
       │   2. record duration, set ExitStatus
       │   3. persist to GRDB blocks + FTS5 index
```

`AnsiSGRParser` covers SGR (16, 256, truecolor; bold, dim, italic,
underline, reset). Cursor moves and DECSET sequences inside Block mode are
silently consumed — they are non-semantic in linear output.

### 8.3 Raw mode internals

Wrap SwiftTerm's `TerminalView` (UIKit) in `UIViewRepresentable`. The
delegate `send(source:data:)` writes user input into the SSH PTY channel.
`feed(byteArray:)` is called from the SSH read stream on the main actor.
Resize is debounced (50 ms) and round-tripped through `session.resize` on
`conduitd` or `SIGWINCH` on the PTY.

`smallest-screen-wins`: when multiple devices attach to the same tmux
session, the daemon publishes the minimum (cols, rows). Cmux taught us
this avoids redrawing nightmares.

### 8.4 Performance budget

- 60 fps scroll on iPhone 15 Pro through 100k lines of scrollback (LazyVStack +
  bounded `Block.chunks` length, with overflow folded into a "show more" marker).
- 16 ms p99 from byte arrival → on-screen for chunks under 4 KB.
- < 80 MB RSS for a 1 MB scrollback session.

### 8.5 Why not Metal-rendered text?

SwiftUI's `Text` and `UITextView`/`TextKit 2` are fast enough for our
volumes and free us from rolling glyph atlases. Ghostty uses GPU rendering
because a desktop user expects 4K @ 120 Hz. On a phone, the bottleneck is
the SSH socket, not the rasterizer. We re-evaluate at M6.

---

## 9. AI integration

### 9.1 The three AI surfaces

1. **NL → command** in the composer (`# rebuild and run tests`).
2. **Explain this output** as a long-press action on any Block.
3. **Approve agent action** as the Inbox card flow (no local LLM call —
   the agent runs remotely; we receive its tool requests through hooks).

There is intentionally **no chat tab** at launch. Chat is the wrong surface
for the steering / approval loop; it competes with the official Claude app
and hides the real work surface (terminal blocks).

### 9.2 Provider abstraction

```swift
public protocol AIClient: Sendable {
    var modelID: String { get }
    func complete(messages: [AIMessage], system: String?, maxTokens: Int) async throws -> String
    func streamCompletion(messages: [AIMessage], system: String?, maxTokens: Int) -> AsyncThrowingStream<AIDelta, Error>
}
```

Concrete clients:

- `AnthropicClient` — claude-sonnet-4-6, claude-opus-4-7, SSE streaming.
- `OpenAIClient` — gpt-5.5, gpt-5.5-mini, responses API.
- `XAIClient` — grok-4 family.
- `MockAIClient` — for tests and demos.

All clients use `URLSession.bytes(for:)` directly. We do not ship a
provider SDK. SSE parsing is 30 lines per provider and saves the binary
size + the maintenance debt of three separate SDKs.

### 9.3 BYOK posture

- API keys are entered once in Settings, stored in Keychain with
  `.whenUnlockedThisDeviceOnly`.
- Keys never leave the device. Requests go direct: `phone → api.anthropic.com`.
- The control plane never sees a user's API key.
- Optional managed AI (a Conduit-hosted relay) is a separate, opt-in tier
  with billing meters.

### 9.4 Agent hook protocol

When `conduitd` is installed and the user has an agent (Claude Code, Codex,
OpenCode, custom) configured, the agent's hook fires a structured event
into `~/.conduit/events/`. `conduitd` serializes these onto the JSON-RPC
side-channel as `agent.approval.pending`, `agent.run.completed`,
`agent.run.failed`. The client surfaces them in the Inbox. The user's
Approve/Reject decision is written back as a hook response file the agent
polls.

This avoids requiring Anthropic / OpenAI to push to our control plane; the
phone has direct line of sight to the workspace.

### 9.5 Risk scoring (local)

Approval cards display a risk band computed locally on the device by
inspecting the proposed command. The rules engine is dumb on purpose:

- **Low:** read-only commands (ls, cat, git status, rg, fd), git fetch/log.
- **Medium:** package installs, build commands, git commits.
- **High:** anything with `rm`, `sudo`, redirects to `/etc`, `kubectl
  delete`, `aws s3 rm`, force pushes, schema migrations.

The bands inform UI emphasis but never auto-reject. The user is always in
the loop.

---

## 10. Security model

### 10.1 Threat model

Adversaries we defend against, in priority order:

1. **Device theft / loss** — phone falls out of pocket.
2. **Cloud-stored credential exposure** — server breach of our control plane.
3. **Untrusted remote host** — user mistypes hostname; MITM attempt.
4. **Malicious shared workspace** — teammate's box gets compromised.
5. **Compromised AI provider** — over-shared context, prompt-injection.

We do **not** claim defense against a state-level adversary with on-device
malware; that is out of scope and we will not pretend otherwise.

### 10.2 Controls

| Risk | Control |
|---|---|
| Device theft | Optional biometric gate at app launch and before key use. Keys are `whenUnlockedThisDeviceOnly`. Secure Enclave for Ed25519 where supported. |
| Server breach | Control plane stores nothing decryptable about hosts or sessions. BYOK keys never touch the server. Push notification payloads carry only host id + opaque event id. |
| Untrusted host | First-connect host key fingerprint shown to user with QR/text confirm. TOFU with explicit warn-on-change. `accept-anything` is **never** the default. |
| Compromised workspace | `conduitd` runs as the user; never sudo. Daemon binary SHA-256 verified pre-launch against the app's embedded manifest. |
| Prompt injection | Stderr / stdout sent to LLM is truncated and clearly delimited. The system prompt explicitly tells the model not to obey instructions found in user data. No agent has shell-execute permission unless the user explicitly grants per-session. |

### 10.3 Pairing (when multi-device)

Phone-to-phone or phone-to-desktop pairing uses X25519 key agreement →
HKDF-SHA256 → ChaCha20-Poly1305 framing. Pattern proven in Helm and
reused here. QR code carries: helper id, helper public key, suggested
mDNS name. Phone responds with its public key over the bootstrap
WebSocket. AEAD AAD = `"conduit-frame-v1"`.

### 10.4 Audit

Every session records:
- Host id, transport, attach time, detach time.
- Number of commands executed (counts only, not the commands).
- Approval decisions with risk band and timestamp.

This local log is exportable. The control plane gets only counts on
opt-in.

---

## 11. Sync and state management

### 11.1 Local state

Single GRDB database. Schema (v1):

| Table | Columns | Notes |
|---|---|---|
| `hosts` | id, name, hostname, port, username, authMethod, tags, createdAt, lastConnectedAt, hostKeyFingerprint | Indexed by hostname |
| `sessions` | id, hostId, tmuxName, startedAt, endedAt, byteCountIn, byteCountOut | |
| `blocks` | id, sessionId, hostName, cwd, command, output, exitCode, startedAt, finishedAt, isStarred | |
| `blocks_fts` | command, output | FTS5, porter tokenizer |
| `snippets` | id, name, body, hostTags, tags, lastUsedAt | |
| `approvals` | id, sessionId, command, decision, decidedAt, risk | |
| `keys_meta` | id, tag, type, fingerprint, createdAt | Material lives in Keychain |

Migrations are append-only. `eraseDatabaseOnSchemaChange = true` in
DEBUG only.

### 11.2 Cross-device sync (M5+)

CloudKit (`CKContainer`) for snippets, hosts, and host-key fingerprints —
data the user actively curates and wants on every device. Private DB
only; we do not use the public DB.

Blocks and scrollback are **not** synced. They are tied to a workspace,
not a user, and pushing terabytes of session logs into CloudKit is
neither cheap nor useful.

CRDT for snippets is a future consideration; LWW on `lastUsedAt` is fine
at launch.

### 11.3 Session continuity

The truth source for session continuity is the **remote `tmux`/`screen`
session**, not the device. On reconnect we enumerate tmux sessions, match
by name, and reattach. The block list is reconciled by replaying the
last K bytes of `tmux capture-pane -pS -K` against the local block FTS.

---

## 12. iOS / iPadOS limitations and workarounds

| Limit | Impact | Workaround |
|---|---|---|
| Apps cannot run shells locally | No on-device build/test/lint | Everything runs remote. We do not pretend otherwise. |
| Background execution is bounded (~30 s after `beginBackgroundTask`) | Long SSH sessions die when phone sleeps | Server-side tmux is mandatory. Reconnect on resume. Optionally use control-plane relay to keep TCP alive across NAT. |
| `URLSessionWebSocketTask` does not survive backgrounding by default | Push side-channel drops on lock | APNs delivers approvals when the WebSocket is dead. The WS is opportunistic, not authoritative. |
| WKWebView cannot speak to localhost on a remote host | Live preview broken out of the box | `SSHProxyURLSchemeHandler`: register `conduit-preview://` scheme and proxy each request through SOCKS-over-conduitd. |
| App size cap on App Store wireless install | TerminalEngine + SwiftTerm + Citadel adds binary weight | Strip bitcode; defer NLP models; ship daemon binaries via OTA download with SHA-256 verify, not in-bundle. |
| iOS keyboard hijacks `Tab` and arrow keys in some contexts | Terminal navigation breaks | Use `UIKeyCommand` with `wantsPriorityOverSystemBehavior` (iOS 15+), capture in `keyCommands` on `UIResponder`. |
| Network framework has no SOCKS client primitive | Cannot reuse system stack for proxy egress | Implement minimal SOCKS5 in Swift; only the CONNECT path is needed. |
| Push payload is 4 KB | Cannot include full diff in notification | Notification carries event id; client fetches on tap. Live Activity holds running state. |
| iCloud Keychain item sharing is brittle across major iOS versions | SSH keys may not round-trip | We do not use iCloud Keychain for SSH keys. Use device keychain + opt-in CloudKit metadata only. |
| `URLSession` does not stream bytes to multiple consumers | SSE consumption forks tricky | Each AI call gets its own URLSession data task; multiplexing is at the engine layer. |

---

## 13. Performance considerations

### 13.1 Targets

| Metric | Target | Measurement |
|---|---|---|
| Cold launch to Workspaces tab | < 800 ms on iPhone 13 | Xcode Instruments |
| Time-to-first-byte after `Reconnect` | < 1.5 s on LTE | OS_signpost |
| Terminal scroll fps | 60 fps sustained | Hitches < 0.5% |
| Memory at 1 MB scrollback | < 80 MB RSS | XCTest performance |
| Battery: 1 h connected idle | < 4% on iPhone 15 | Instruments / Energy Log |
| AI streaming latency (NL→cmd) | < 1.5 s to first token | Anthropic SSE p50 |

### 13.2 Strategies

- **Lazy everything.** `LazyVStack` for blocks. `LazyVGrid` for files.
- **Bound scrollback in memory.** Keep last 2000 blocks hot; older blocks
  page from GRDB on scroll.
- **AttributedString is immutable.** Cache rendered AttributedStrings per
  block; invalidate on theme change only.
- **Bounded chunk size.** Coalesce SSH reads to 64 KB max before
  publishing; smaller chunks cause @Observable thrash.
- **No JSON on the hot path.** SSH frames are bytes; JSON-RPC is only
  for control events.
- **Background queue for FTS5 writes.** Block insert returns before the
  FTS update completes.

---

## 14. Roadmap

The "M" milestones are vertical slices. Each one ships a working,
testable app.

| M | Title | What ships | What this proves |
|---|---|---|---|
| **M0** | Scaffolding | SwiftPM workspace, modules, app shell, ARCHITECTURE.md | Dependency graph compiles |
| **M1** | First connect | Add host, ed25519 keygen in Keychain, SSH connect, run one command, see blocks | The fastest possible "I see my server from my phone" |
| **M2** | Real terminal | SwiftTerm raw mode for TUI apps, mode switch heuristic, keyboard accessory rail | vim/htop/tmux work |
| **M3** | Survive | ReconnectController, tmux replay, Mosh evaluation, basic push | Sessions don't die on Wi-Fi switch |
| **M4** | AI loop | Anthropic + OpenAI clients, `#` NL→cmd, explain-block, BYOK | The core differentiator works |
| **M5** | Inbox + Approvals | conduitd MVP, agent hook ingest, approval cards, risk scoring | Phone steers Claude Code in another window |
| **M6** | Preview | SSHProxyURLSchemeHandler, SOCKS-over-RPC, port auto-detect, WKWebView surface | Show your dev server from your phone |
| **M7** | Diff + Files | DiffKit, file explorer, SFTP put/get, image upload composer | Review the agent's work without a laptop |
| **M8** | Snippets + Workflows | Snippet library, parameterized snippets, host-scoped presets | Heavy-user retention |
| **M9** | iPad and external KB | Split view, hardware keyboard parity audit, drag-and-drop | iPad-pro power users |
| **M10** | Sync + polish | CloudKit snippets/hosts, theme picker, App Store prep | Multi-device |
| **M11** | Managed compute (opt-in) | One-tap Fly.io / Lightsail / OrbStack host provisioning | Onboarding for non-server-owners |

Each milestone has a written demo script (in `docs/demos/MX.md`) that must
pass on a real device before the milestone is closed.

---

## 15. Gaps in the market we explicitly fill

Synthesized from research report, competitor issue trackers, and Helm /
warp-mobile learnings.

1. **No competitor offers Inbox + Terminal + Preview + Diff in one app
   designed for the phone form factor.** Helm has approvals but no general
   terminal. Termius has terminal but no inbox. Nimbalyst has review but no
   terminal. We unify them.

2. **No competitor uses a SHA-256-verified single-binary helper for
   advanced features.** cmux is the only one that does this on desktop; on
   mobile, nobody. Our `conduitd` is opt-in and the verification path
   matches Apple's notarization mental model, so users in regulated
   environments can ship it.

3. **No competitor exposes a Live Activity for running agent tasks.** A 30
   minute test run currently means the user has to keep checking. We
   surface progress on the Lock Screen and Dynamic Island.

4. **No competitor has a serious local risk-scoring layer on agent
   commands.** Claude's Allow/Deny in the official app is binary. We add a
   risk band, a 24-h "always allow this exact pattern" override, and a per-
   workspace allowlist.

5. **No competitor handles SSH + WebView preview cleanly on mobile.**
   Helm's curl-over-SSH is brilliant but synchronous. We push it to proper
   SOCKS-over-RPC so websockets and HMR work.

6. **No competitor lets you set up an agent CLI on a fresh box from the
   phone alone.** Onboarding has a "Set up Claude Code on this host"
   one-tap action that runs the upstream install script via SSH and
   verifies success.

---

## 16. Open questions and active decisions

These are decisions we will revisit; recording them prevents re-litigation.

| # | Question | Current direction | When we revisit |
|---|---|---|---|
| Q1 | Mosh: vendor `mosh-client` as Swift package or wait? | Wait until M5; tmux + reconnect covers 80% | After M3 dogfood |
| Q2 | Diff syntax highlighting: SwiftTreeSitter or hand-rolled? | SwiftTreeSitter | After M7 perf test |
| Q3 | Use Anthropic SDK / OpenAI SDK or hand-rolled URLSession? | Hand-rolled | If a provider adds tools we cannot trivially port |
| Q4 | CloudKit vs custom sync server? | CloudKit | When we need cross-org sync |
| Q5 | Local LLM (Apple Intelligence / WhisperKit) for offline NL→cmd? | Out of scope at launch | When Apple Intelligence on-device proves capable |
| Q6 | Run conduitd as a systemd unit or per-ssh-session? | Per-ssh-session via `exec` channel | If users ask for proactive event push |
| Q7 | License model for engine modules? | Likely MIT/Apache for engines | Before App Store submission |

---

## 17. Anti-patterns we have already rejected

Listing failures-of-imagination so we do not repeat them in code review.

- **"Just embed a webview with Theia."** — Rejected. Adds JS runtime weight,
  fights iOS gesture system, and we lose accessibility and native input.
- **"Wrap VS Code's web build."** — Same problem; also a licensing surface.
- **"Synchronize the entire repo to the device."** — Wrong direction.
  Remote-first means files live remote.
- **"Stream the entire scrollback into Anthropic for each prompt."** — Cost
  and privacy bomb. Use sliding window with explicit "include output"
  button on each block.
- **"Polish a single-host experience and then add multi-host."** — Helm did
  this, it created backbox decisions hard to unwind. We model multi-host
  from M1.
- **"Use raw `DispatchQueue.global().async` for SSH reads."** — Loses
  cancellation, hides errors, and fights Swift Concurrency. Always `Task`.
- **"Use the Anthropic Python SDK via PythonKit."** — Hard no. Adds Python
  runtime to the app. Use URLSession + 30 lines of SSE.

---

## 18. References

Internal:

- `/Users/roshansilva/warp-mobile/` — warp-mobile scaffold (Block model,
  Citadel actor pattern, AnsiSGRParser).
- `/Users/roshansilva/Documents/ios/` — Helm app (SwiftTerm wiring,
  SSHProxyURLSchemeHandler, X25519 pairing, keyboard preset rail).
- `/Users/roshansilva/Documents/mobile-coding/` — Mobile-coding React
  prototype + research report and notes.

External products and docs:

- [Termius — Mobile Terminal](https://support.termius.com/hc/en-us/articles/12482919487385-Mobile-Terminal)
- [Termius — New Touch Terminal on iOS](https://termius.com/blog/new-touch-terminal-on-ios)
- [Blink Shell](https://blink.sh/)
- [Warp](https://warp.dev/) and [warpdotdev/warp](https://github.com/warpdotdev/warp)
- [cmux — manaflow-ai/cmux](https://github.com/manaflow-ai/cmux)
- [Ghostty](https://ghostty.org/)
- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm)
- [Citadel](https://github.com/orlandos-nl/Citadel) / [swift-nio-ssh](https://github.com/apple/swift-nio-ssh)
- [Anthropic Messages API](https://docs.anthropic.com/en/api/messages)
- [Apple — iOS & iPadOS Release Notes](https://developer.apple.com/documentation/ios-ipados-release-notes)

Research basis:

- `/Users/roshansilva/Downloads/deep-research-report (2).md` — Building
  a Mobile-First AI Coding App (May 2026, web-sourced).

---

## 19. Third-party dependency notes

### 19.1 Forked swift-nio-ssh (Wellz26/swift-nio-ssh)

**Status:** active — currently pinned at `0.3.4..<0.4.0`

**What it is:** `Package.swift` pins `github.com/Wellz26/swift-nio-ssh` rather than the canonical
`apple/swift-nio-ssh`. This is the community-maintained fork that the `Citadel` SSH library
(`orlandos-nl/Citadel`) depends on internally. We do not fork it independently; we follow
Citadel's transitive requirement.

**Why the fork exists over upstream:**

| Patch | Status in apple/swift-nio-ssh |
|---|---|
| Mac Catalyst: add NIO product dependency to NIOSSH target | Not merged upstream |
| SSH certificate authentication (`AuthenticationMethod.certificate`) | Not in upstream |
| visionOS / Musl / Bionic conditional-import directives | Not in upstream |
| Multiple MACs per transport | Not in upstream |

The Mac Catalyst patch is the immediate blocker — without it the NIOSSH product fails to link
under Catalyst. The certificate auth patches are used by Citadel for advanced server-side auth
flows.

**Upstream tracking plan:**

1. Watch `apple/swift-nio-ssh` releases; the Mac Catalyst fix is the primary switch-back trigger.
2. Watch `orlandos-nl/Citadel` — when Citadel itself migrates its own `Package.swift` to
   `apple/swift-nio-ssh`, update our pin to match.
3. Consider filing a PR against `apple/swift-nio-ssh` for the Mac Catalyst fix if it remains
   unmerged after the next minor release of NIO.

**Switch-back trigger:** `apple/swift-nio-ssh` incorporates the Mac Catalyst product-dependency
fix **AND** Citadel updates its resolved dependency to the upstream package. Both conditions
must hold before this repo can switch back — one without the other would break the Citadel
integration.

**Follow-up:** Review this decision at the next Citadel version bump or when
`apple/swift-nio-ssh` > 0.4.0 lands.

---

### 19.2 Crash reporting (Sentry)

Sentry is wired in `Conduit/ConduitApp.swift` via `SentrySDK.start`. Configuration notes:

- **DSN:** Set the `sentryDSN` constant in `ConduitApp.swift` before App Store release.
  Create a project at your Sentry instance (cloud or self-hosted) to obtain the DSN.
- **Opt-out:** Set `UserDefaults` key `dev.conduit.crashReportingOptedOut = true` to disable at
  runtime. No PII is collected (`sendDefaultPii = false`). No performance tracing
  (`tracesSampleRate = 0`). No advertising or tracking.
- **Privacy manifest:** `Conduit/PrivacyInfo.xcprivacy` declares `NSPrivacyAccessedAPICategorySystemBootTime`
  (reason `35F9.1` — crash reporting) and `NSPrivacyCollectedDataTypeCrashData` (no linking, no tracking).
- **Verifying symbolication:** In `configureSentry()` there is a commented-out `SentrySDK.crash()`
  line under `#if DEBUG`. Temporarily un-comment, run on a real device, recomment, and check your
  Sentry dashboard for a symbolicated report.

---

*End of ARCHITECTURE.md. Changes require a PR labeled `architecture`.*
