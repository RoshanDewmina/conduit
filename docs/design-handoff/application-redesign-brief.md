# Lancer — Application Redesign Brief (for Claude Design)

> Self-contained. You do **not** need to read the source. Goal: a simpler, faster, more visual Lancer
> that makes one thing unmistakable — **approve and steer your coding agents from your phone.**
>
> **Screenshots — read this first.**
> - `docs/design-handoff/app-screenshots/` — **real app**, captured 2026-06-23 from the current build (post-cleanup). These are the source of truth for the *current* design language.
> - `docs/audits/screenshots/` — earlier renders of the production SwiftUI components (the in-app preview harness that produced them has since been **deleted**, so they can't be regenerated). Treat as design reference for shipping components, not as live screens.
> - **Removed as old-design prototypes** (deleted from code this pass, do not design around them): "Agent Features", "Agent HUD / island", "Proof Card", the "Sessions glyph gallery", and the "Typed Inbox" prototype.
>
> Supporting audit: `docs/audits/*.md`.

---

## Product overview

- **What it is:** Lancer is an iOS "mission control" for AI coding agents (Claude Code, Codex, OpenCode, Kimi) that run on the developer's **own** machines/servers. The phone **steers and approves**; it is **not** a phone IDE.
- **Who it's for:** developers who run autonomous/long-running coding agents and want to supervise, approve risky actions, and continue work from their phone.
- **Problem it solves:** agents block on risky actions (or run unsupervised). Lancer routes those moments to your phone as **governed approvals**, with full context, so you can approve/deny/continue from anywhere — even with the app closed (lock-screen push).
- **Core value proposition:** *Your coding agents, supervised from your pocket.* Approve actions from afar · watch the terminal stream live · policy guardrails per host.
- **Primary user journeys:**
  1. **Pair** a machine (run `lancerd pair`, scan a code).
  2. **Dispatch** an agent from New Chat (pick agent, repo, prompt).
  3. **Approve / deny** when it hits a gated action (in-app, lock-screen, or Watch).
  4. **Continue** the conversation / follow up.
- **Product terminology:** *daemon* (`lancerd`, the resident host agent) · *relay* (the encrypted phone↔host transport) · *approval / governed action* · *policy* (allow/ask/deny rules) · *autonomy preset* (Balanced/Permissive/Restrictive) · *fleet / machines* · *dispatch* · *continue/follow-up* · *drift* (host setup drift) · *quota guard* (spend caps).
- **Platforms:** iOS (primary), iPadOS (split view), watchOS (approvals), macOS menu-bar companion (`LancerMac`). This brief is **iOS-first**.

---

## Current application

### Navigation (today)
Sidebar / Command-Home shell (no tab bar). 6 primary destinations:
**Home · New Chat · Thread (recent) · Inbox (Needs Attention) · Machines (Fleet) · Settings.**
Plus a full-screen SSH terminal, ~12 Settings sub-screens (down from ~20 after cleanup), and sheets for add-machine / pairing / activity. The recommended target (see `ux-simplification-report.md`) is **4** primary destinations (fold Inbox into Home).

### Every screen + purpose (each tied to its real-app capture)
- **Home** (`real-01-home.png`) — editorial header ("Good evening / 2 agents need you"), a warm **attention card** ("WAITING ON YOU · N conversations blocked →"), and a **YOUR MACHINES** list (collapsible host rows with project counts). Hamburger (top-left) opens the drawer; **+** (top-right) starts a new chat. *Strongest screen — the product's home base.*
- **Sidebar drawer** (`real-02-sidebar.png`) — profile/account header, **New chat** CTA, search, primary nav (Home · Inbox · Machines), recent-threads list, Archived entry, relay-status footer.
- **New Chat** (`real-06-newchat.png`) — dispatch composer empty state: centered "New chat / Describe the work. Lancer routes it through policy before anything runs.", a bottom message field ("/ for commands, @ for files…"), and a **Pick agent · host** selector + options button. Sends become a live transcript with tool/diff/terminal cards. *Strongest screen.*
- **Thread / Chat history** (`ChatHistoryView.swift`) — **read-only transcript** of a persisted conversation opened from the sidebar recents. Header shows title · host · agent; body renders persisted turns straight from the repo (deliberately stateless so reopening never inherits a stale "thinking" run). A follow-up composer at the bottom **continues** the conversation (resolves a live channel, new runId per turn). *No fresh capture — see capture list.*
- **Inbox / Needs Attention** (`real-03-inbox.png`) — "N agents are waiting"; stacked **approval cards** showing agent, time, **risk pill** (HIGH RISK / MEDIUM), the exact command (e.g. `rm -rf ./dist && npm run build:prod`), and **Deny / Approve**. The system-of-record for governed actions. *Strongest pattern.*
- **Machines / Fleet** (`real-04-machines.png`) — selected host header ("Dev VPS · online·healthy", RELAY badge), **agents-on-host** card, a stat row (Usage today / Connection / Setup drift), a "Usage & limits" link, and a **Saved hosts** list (relay + SSH). Host detail can open a live terminal.
- **Settings** (`real-05-settings.png`) — clean landing grouped into **Policy & Governance** (Default autonomy, Enforcement log, **Emergency stop**) and **General** (Appearance, Accent, Provider keys, Notifications), with the Lancer Pro account card on top. The sprawl is in its *depth* (~12 sub-screens), not this landing.
  - **Settings → Provider keys** (`real-07-settings-providerkeys.png`) — "API keys go directly from your device to the provider. Lancer never sees them." Per-provider rows (Anthropic, OpenAI) with "not set" + paste field. Representative of the settings-detail pattern.
- **Terminal / live session** (`SessionFeature/SessionView.swift`) — power-user SSH PTY rendered as **command blocks** (OSC-133), with a custom terminal keyboard panel (keys/snippets tabs), snippet palette, port-forward, raw-history toggle, dictation, and tmux sheet. Reached from a Machine's "Open terminal".
- **Onboarding** (`OnboardingRedesignView` in `OnboardingRedesignGalleryView.swift`) — production 4-step: **value hero** ("your machines, in your pocket" + 3 feature rows) → **pair** (run `lancerd pair`, scan QR / 6-digit) → **policy preset** ("How cautious?") → optional **SSH setup**. Account entry (`AccountEntryView`) precedes it. Legacy 7-step flow deleted. Value-screen render in `docs/audits/screenshots/onboarding/onboarding-redesign.png`.
- **Approval card** — risk, command, diff, blast-radius, approve/deny/edit, rendered **inline in the Inbox** (see `real-03-inbox.png`). The standalone `DSDecisionSheet` prototype was unused and has been removed.

### Secondary / detail screens (described from source — no fresh capture)
- **Inbox approval detail** — tapping a card expands command, typed `tool_use` input, diff/blast-radius, and Edit-&-Run / Allow-Always actions.
- **Machine detail** (`FleetView` selection) — per-host health, agents-on-host, usage/quota, setup-drift, Open terminal; saved-host rows reconnect.
- **Settings → Default autonomy** (`AutonomyLevelView`) — Balanced / Permissive / Restrictive preset picker (also the onboarding policy step).
- **Settings → Enforcement log** (`AuditView`) — hash-chained audit feed of agent actions + decisions; verify/export.
- **Settings → Emergency stop** — halts every running agent across SSH + relay (destructive, confirm).
- **Settings → Notifications / Appearance / Accent** (`NotificationsSettingsView` / `AppearanceSettingsView` / `AccentSettingsView`) — push severity; theme/mode (note: app renders fixed-dark, so Appearance is largely a no-op); brand accent (5 themes).
- **Settings → Trust & privacy** — Relay pairing (`E2ERelayPairingView`, QR), Paired devices (`DeviceManagementView`, revoke).
- **Settings → Secrets** (`SecretsView`) — broker: store/list/authorize/revoke per-agent secret requests.
- **Settings → Doctor** (`DoctorView`) — host diagnostics run + findings.
- **Settings → Billing / Paywall** (`BillingView` / `PaywallSheet`) — Lancer Pro entitlement + IAP.
- **Add machine** — chooser (relay-pair vs SSH); SSH path = Add host wizard (`AddHostView`) → Host editor (`HostEditorView`).
- **Archive** (`ChatArchiveView`) — archived threads, restore/delete.
- **Drift findings** (`DriftFindingsView`) — per-host setup-drift list (post-launch moat).
- **Quota guard / Usage** (`QuotaGuardView`) — per-provider spend + daily/monthly caps.
- **Relay file browser** (`RelayFileBrowserView`) — browse host files over the relay (`@`-mention source).
- **Diff / file preview** (`DiffFeature/DiffView`, `FilesFeature/FilePreviewView`) — staged diff with Ship-It; read-only file preview. Renders in `docs/audits/screenshots/files/`.

### Important states (verified against the real build 2026-06-23)
Empty/first-run (`real-home-empty-firstrun.png` — "All clear tonight" + **notification permission prompt**), populated (`real-home-populated.png` — "N agents need you", attention card, "Connect a machine"), permission prompt (`real-home-permission-prompt.png`). Plus (from code/component renders): loading (several screens render blank >1.5 s on entry — needs skeletons), error/offline, approval pending/approved/denied, SSH connecting/connected/slow/failed (orb states), camera permission (QR).
**Correction to the earlier audit:** the "2 conversations blocked with zero machines" state was **persisted demo-seed data** (`LANCER_SEED_DEMO`), not hardcoded — a clean install correctly shows "All clear tonight." The real defect is that demo seed data persists into normal runs; the redesign's empty state should be the clean one.

### Existing design direction
Distinctive **editorial dark** theme. Fonts: Bricolage Grotesque (display), Hanken Grotesk (body), JetBrains Mono (technical), **Instrument Serif italic** for editorial accents ("Good evening"). Warm **terracotta** accent + a green/amber/red **risk ramp**. Full token system (`Tokens.swift`), ~42 reusable components, Dynamic Type supported. **This is a strong base to refine, not replace.**

### Strongest current screens
**Home** (`real-01-home.png`) · **Inbox** approval cards (`real-03-inbox.png`) · **Settings** grouping (`real-05-settings.png`) · **New Chat** (`real-06-newchat.png`). Use these as the visual north star. Note: Settings' *top level* is already well-grouped — the sprawl is in its **depth** (~20 sub-screens), not its landing.

### Weakest / legacy screens
Onboarding account+SSH screens (text-heavy, value-late) · the agent-detail views · Settings (overloaded) · orphaned hosted-cloud/loops/worktrees/SFTP screens (not in nav) · blank-on-entry async screens.

### Codebase cleanup already done (2026-06-23, build-verified)
To reduce sprawl before redesign, the following were **deleted** (builds green, app + package):
the entire **debug gallery harness**, the **legacy 7-step onboarding** flow (production uses the 4-step redesign), the duplicate **KeysView** module + legacy **FilesView**/**AgentsView**, both repo `archive/` dirs, and ~13 **orphaned prototype components/sheets** (incl. the 5 old-design screens above). Net ≈ **−8,000 LOC**. **Kept** (your earlier decision): the deferred-V2 code (hosted-cloud, loops, worktrees). So the live surface is now meaningfully smaller than the original audit's screen-inventory implies.

### Real screen captures (full set, 2026-06-23)
All driven through the **real running app** via XCUITest navigation against the app's populated-state seams (`LANCER_UITEST_RESEED` + `LANCER_FAKE_RELAY_HOST`) — not the (now-deleted) gallery. In `app-screenshots/`:
- `real-01-home.png` — Home: "N agents need you", attention card, machines.
- `real-02-sidebar.png` — the sidebar drawer (Home/Inbox/Machines, recent chats, relay footer).
- `real-03-inbox.png` — **Inbox**: live approval cards (e.g. `rm -rf ./dist && npm run build:prod` HIGH RISK, `git push --force-with-lease` MEDIUM) with Deny/Approve.
- `real-04-machines.png` — **Machines/Fleet**: a relay host ("Dev VPS", online·healthy), agents-on-host, usage/connection/setup-drift stats, saved SSH hosts.
- `real-05-settings.png` — **Settings**: cleanly grouped — Policy & Governance (Default autonomy, Enforcement log, **Emergency stop**) + General (Appearance, Accent, Provider keys, Notifications).
- `real-06-newchat.png` — **New Chat** composer empty state ("Describe the work…", agent/host picker).
- `real-home-empty-firstrun.png` / `real-home-permission-prompt.png` — clean empty state + notification permission prompt.

### 📸 Screens to capture yourself (couldn't get a clean real shot this session)
Populate the app first: launch with **`LANCER_UITEST_RESEED=1 LANCER_FAKE_RELAY_HOST=1`** (in Xcode scheme → Run → Arguments → Environment, or `SIMCTL_CHILD_…` via `simctl launch`). Dismiss the notification prompt once. Then navigate:

| # | Screen | How to reach it |
|---|---|---|
| 1 | **Chat thread / transcript** | Home or sidebar → tap a **recent thread** row (`ChatHistoryView`). The core conversation view. |
| 2 | **Inbox approval — expanded detail** | Inbox → tap an approval **card body** (not the Approve button) to expand typed input / diff / Edit-&-Run. |
| 3 | **Live terminal / session** | Machines → a host → **Open terminal** (needs a reachable SSH host; the block-render UI is in `SessionView`). |
| 4 | **Onboarding flow** (4 steps) | Fresh install / reset onboarding → value → pair → policy → SSH. (Value step also in `audits/screenshots/onboarding/`.) |
| 5 | **Settings → Default autonomy** | Settings → Default autonomy (`AutonomyLevelView`). |
| 6 | **Settings → Enforcement log** | Settings → Enforcement log (`AuditView`). |
| 7 | **Settings → Notifications / Appearance / Accent** | Settings → General → each row. |
| 8 | **Settings → Trust & privacy** (Relay pairing, Paired devices) | Settings → Trust → Relay pairing / Paired devices. |
| 9 | **Settings → Secrets / Doctor / Billing** | Settings → respective rows. |
| 10 | **Machine detail** | Machines → tap a saved host row. |
| 11 | **Add machine** (chooser + SSH wizard + host editor) | Home `+` / Machines → Add a machine. |
| 12 | **Archive** | Sidebar → Archived. |
| 13 | **Drift findings / Quota & usage** | Machines → Setup drift card / Usage & limits. |
| 14 | **Relay file browser** | New Chat composer → `@` (file mention) or Machines → host files. |
| 15 | **Diff / file preview** | Open a run with changed files → Diff (`DiffView`); also `audits/screenshots/files/`. |

Save these into `app-screenshots/` with matching `real-NN-<name>.png` names and they'll slot into the descriptions above.

---

## Feature constraints

### Must remain (V1 core — backend-proven)
- Pair via encrypted relay; multi-vendor **dispatch** + **continue/follow-up**.
- **Governed approvals** (allow/ask/deny policy; approve/deny/edit; lock-screen push while app closed — verified on device).
- **Machines/fleet** with health, **quota guard** (spend caps), **setup-drift** detection.
- **Audit log** (hash-chained), **secrets broker**, **policy** (preset + YAML), **billing/IAP**.
- Power-user **SSH terminal** (secondary path) and **observed sessions** (read-only transcripts).

### Backend capabilities that need UI (today thin/absent)
- Pause/resume a run (RPC exists, **no button**).
- Schedules (cron) and Loops (backend exists, **no real UI**) — *future*.
- CI events / git-clone (backend-only) — *future*.

### Future-only (retain, keep OUT of V1)
Hosted-cloud execution (run agents in the cloud + prepaid credits + Provider/Hosted/SelfHostVsHosted screens), multi-cloud agent-runner, scheduling, loops, worktrees, SFTP file browser.

### May be removed / deferred
Legacy onboarding flow; AgentOrg; Appearance setting (fixed-dark no-op); duplicate Keys/Audit/Premium-comparison screens; 7 of 8 agent-detail views.

### Technical / platform constraints
- iOS-first; iPad split-view; Watch approvals; fixed-dark in practice.
- Approvals are **fail-closed** and time-boxed (~120 s) — the UI must make pending/expiry states legible.
- Sensitive data (commands, secrets) must stay redacted in notifications/lock-screen.
- Keep Dynamic Type; respect reduce-motion (currently unwired).

---

## Redesign objectives
1. **Simpler navigation:** 6 roots → **4** (Home · New Chat · Machines · Settings); fold Inbox into Home.
2. **Fewer views:** Settings ~20 → ~12 (4 groups); agent-detail 8 → 1; remove duplicates; defer V2 surfaces.
3. **Less text:** cut onboarding/SSH/policy prose; show, don't explain.
4. **More visual communication:** lean on the editorial system + iconography for value and state.
5. **Faster route to value:** value screen first; account/SSH optional & contextual; onboarding 5–7 → **3**.
6. **Consistent visual system:** one filled button; snap spacing to scale; skeletons for async; true empty states.
7. **Clearer hierarchy:** core approve-loop foregrounded; power-user (terminal, YAML, secrets) de-emphasized.
8. **Complete state coverage:** loading/empty/error/offline/permission for every surface.
9. **Reusable components:** consolidate to the proven DS set; add skeleton + empty-state components.
10. **Accessibility:** label icon-only controls; wire reduce-motion; keep Dynamic Type.

---

## Required outputs from Claude Design
1. **Revised information architecture** — 4-destination model; where Inbox, policy, audit, terminal, secrets live.
2. **Simplified navigation** — sidebar/home shell refined; how depth (machine detail, run detail, approval) is reached.
3. **Revised onboarding flow** — 3 required screens (value → pair → caution) + optional account/SSH; minimal copy per screen; show-don't-tell visuals.
4. **Screen-by-screen redesign** — every retained screen in the inventory, with the strongest current screens as the reference language.
5. **Component system** — consolidated buttons/cards/chips/headers/sheets + new skeleton & empty-state components; states for each.
6. **Typography & spacing system** — formalize the 4-font scale; a single spacing scale with documented exceptions.
7. **Interaction & motion** — approval flow choreography (pending → decision → result); reduce-motion variants; haptics for approve/deny.
8. **Loading / empty / error / offline states** — a standard pattern set applied everywhere (kill blank-on-entry).
9. **Accessibility** — labels, Dynamic Type caps, reduce-motion, 44pt targets, contrast on the dark theme.
10. **Migration map** — old screen → new screen (incl. merges/removals), so engineering can re-route deterministically.

### Success criteria
A new user understands "approve my agents from my phone" within one screen; reaches a working paired state in ≤3 onboarding screens; and the entire core loop (dispatch → approve → continue) lives across ≤4 primary destinations with consistent states throughout.
