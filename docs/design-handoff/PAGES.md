# Lancer — Page-by-Page Design Handoff

## What Lancer is

Lancer is an iOS control plane for AI coding agents. You connect it over SSH to any host you
own (a VPS, a Pi, your Mac) that runs the `lancerd` resident daemon. When an agent on that host
(Claude Code, Codex, Cursor, …) wants to run a command, write a file, or call an MCP tool, Lancer
turns that request into a **typed approval card on your phone** — you APPROVE / DENY / ALLOW-ALWAYS /
EDIT&RUN, and the agent unblocks. It is a **passive approval loop**, not a dispatch console: the
job is "review what your agents want to do, from anywhere," plus a Warp-style block terminal for
when you want to drive the host directly. A paid Lancer Cloud tier adds hosted agents, push relay,
and metered cross-vendor AI spend.

### Design language

- **Terminal / BLOCKS aesthetic, dark-first.** Monospace (`.dsMonoPt`) for commands, hostnames,
  prompts, and metadata; a humanist sans for prose. Output renders as Warp-style **blocks** with a
  left state gutter, `$ command` bar, and an exit chip (`✓ exit 0` / `✗ exit 1`).
- **`DSScreenHeader` prompt headers.** Every primary screen opens with a lowercase glyph title and a
  blinking `_` cursor (`inbox_`, `fleet_`, `library_`), a `~/lancer › <breadcrumb>` line, and a
  full-width spectrum rule. This is the single most recognizable element — keep it consistent.
- **Risk as color.** Approval cards carry a severity chip (LOW/MED/HIGH/DESTRUCTIVE) that tints the
  card's left bar — green→amber→red. The pixel-art `PixelBox`/`PixelAvatar` motifs seed agent state
  and host identity deterministically.
- **Tokens & components:** `Sources/DesignSystem/Tokens.swift`, `Sources/DesignSystem/Components/`.
  Canonical gallery: `Sources/AppFeature/DebugGalleryView.swift`.

### How to read this doc

Screenshots live in `screenshots/` as `NN-<screen>-<state>-<appearance>.png`. Each page lists its
captured files. "Real-app" = navigated in the running app; "Gallery" = `LANCER_GALLERY=<route>`
debug harness (used for screens needing a live session or seeded data).

---

## Pages

### 00 · Onboarding
- **Job:** first-run value pitch — "approve agent actions from your phone," BYO-host framing, no account.
- **Entry:** first launch before any host is saved (`onboardingSeen == false`).
- **DS components:** `OnboardingView`, `DSScreenHeader`-style hero, `DSButton` primary CTA.
- **States:** populated (the only state).
- **Shots:** `00-onboarding-populated-dark.png`, `00-onboarding-populated-light.png`. *(Gallery: `onboarding`)*

### 01 · Inbox (primary tab)
- **Job:** the core surface — pending agent approvals as typed cards; approve/deny/allow-always/edit.
- **Entry:** default tab on launch; APNs push deep-links here.
- **DS components:** `DSScreenHeader`, `DSApprovalCard` (risk chip + `$ command` + 4 actions),
  `DSAutonomyPresetBar`, decided-row strip with status chips (`approved`/`always`).
- **States captured:** populated (2 pending + 1 decided), empty ("inbox zero — Agents are running clean").
- **Shots:** `01-inbox-populated-{dark,light}.png`, `01-inbox-empty-{dark,light}.png`. *(Real-app: `LANCER_TAB=inbox`)*

### 05 · Inbox — typed approval cards (Ask-Question + MCP-call)
- **Job:** richer approval kinds beyond shell commands — agent asks a multiple-choice question; agent
  requests an MCP tool call with args.
- **Entry:** Inbox, when the pending item is a question or MCP call (driven by the agent's request kind).
- **DS components:** `DSAskQuestionCard` (A/B/C/D choices + SUBMIT), `DSMCPCallCard`
  (tool name + `tool use` id + args + deny/always/edit&run/approve), `DSAutonomyPresetBar`.
- **States:** populated.
- **Shots:** `05-inbox-typed-approval-{dark,light}.png`. *(Gallery: `inbox-typed`)*

### 02 · Fleet (tab)
- **Job:** your saved hosts + a spend/sessions summary; reconnect to a host; see live agents per host.
- **Entry:** Fleet tab.
- **DS components:** `DSScreenHeader`, summary stat card (vendors / sessions / $today), saved-host rows
  (`PixelAvatar` + name + `user@host:port` + reconnect glyph in a fixed-width slot), `DSEmptyState`.
- **States captured:** populated (5 seeded hosts), empty ("No agents connected — Connect a host").
- **Shots:** `02-fleet-populated-{dark,light}.png`, `02-fleet-empty-{dark,light}.png`. *(Real-app: `LANCER_TAB=fleet`)*

### 03 · Activity (tab) — "while you were away"
- **Job:** the audit feed of what agents did while you weren't watching (`agent.audit.tail`).
- **Entry:** Activity tab.
- **DS components:** `DSScreenHeader` (breadcrumb "while you were away"), `BridgeAuditFeedView` mono
  rows, `DSEmptyState(.server, "not connected")`.
- **States captured:** not-connected (the empty/disconnected state). A populated feed requires a live
  SSH session with audit history — see "couldn't capture" note below.
- **Shots:** `03-activity-notconnected-{dark,light}.png`. *(Real-app: `LANCER_TAB=activity`)*

### 04 · Settings (tab)
- **Job:** AI provider + API keys (on-device Keychain), appearance, security (Face-ID lock, redact
  secrets, audit log), agent-approval policy, notification filters, integrations, billing, about.
- **Entry:** Settings tab. Folder icon (top-right) → Library.
- **DS components:** `DSScreenHeader` + trailing `DSIconButton`, provider picker, secure key fields,
  segmented theme control, `DSListSectionHead` sections, nav rows, switches.
- **States:** populated.
- **Shots:** `04-settings-populated-{dark,light}.png`. *(Real-app: `LANCER_TAB=settings`)*

### 11 · Billing & usage
- **Job:** Lancer Pro (one-time) status + Lancer Cloud status + metered AI-usage-today.
- **Entry:** Settings → "Billing & usage".
- **DS components:** `BillingView`, `DSScreenHeader`, status cards with verified/restore rows, footnote.
- **States:** populated (Pro unlocked, Cloud active).
- **Shots:** `11-billing-{dark,light}.png`. *(Gallery: `billing`)*

### 12 · Paywall
- **Job:** convert to Lancer Pro — "pay once, yours forever," one-time $14.99, no subscription.
- **Entry:** tapping a Pro-gated feature (e.g. partial-hunk diff); Settings.
- **DS components:** `PaywallSheet`, big display headline, price block, primary unlock button, restore link.
- **States:** populated. *(StoreKit "product not found" line is a simulator-only testing artifact — the
  layout is final; on-device with the StoreKit config it shows the live product.)*
- **Shots:** `12-paywall-{dark,light}.png`. *(Gallery: `paywall`)*

### 13 · Premium comparison (Free vs Pro)
- **Job:** feature matrix justifying the upgrade.
- **Entry:** Settings → "Compare Free vs Pro"; paywall.
- **DS components:** `PremiumComparisonView`, `DSScreenHeader` ("upgrade_"), two-column check matrix,
  pinned unlock CTA.
- **States:** populated.
- **Shots:** `13-premium-compare-{dark,light}.png`. *(Gallery: `compare`)*

### 14 · Library (your toolkit)
- **Job:** hub for reusable snippets, SSH keys, and (cloud) agents — one-tap reuse.
- **Entry:** Settings → folder icon.
- **DS components:** `LibraryView`, `DSScreenHeader` ("library_"), `DSCategoryCard` grid (count + label +
  subtitle), `DSEmptyState`.
- **States captured:** populated (Snippets 7 · SSH Keys 0 · Agents locked), empty ("nothing saved").
- **Shots:** `14-library-populated-{dark,light}.png`, `14-library-empty-{dark,light}.png`. *(Real-app)*

### 15 · Library → Snippets
- **Job:** browse/filter reusable command snippets; tap to run on the active host.
- **Entry:** Library → Snippets card.
- **DS components:** `SnippetsLibraryView`, `DSScreenHeader` ("snippets_"), category filter chips
  (all/ops/debug/data), snippet rows (name + tag chip + `$ command` + run arrow).
- **States:** populated (7 snippets).
- **Shots:** `15-library-snippets-{dark,light}.png`. *(Real-app)*

### 16 · Library → SSH Keys
- **Job:** generate/manage Secure-Enclave-backed Ed25519 keys for password-less auth.
- **Entry:** Library → SSH Keys card.
- **DS components:** `KeysManagementView`, `DSScreenHeader` ("ssh keys_"), "+ generate ed25519 key"
  dashed action, `DSEmptyState` ("no keys yet").
- **States captured:** empty (keys are enclave-backed and can't be seeded; empty is the default state).
- **Shots:** `16-library-keys-{dark,light}.png`. *(Real-app)*

### 17 · Policy editor (Agent policy)
- **Job:** edit the host's `~/.lancer/policy.yaml` — which agent actions auto-allow / ask / deny by risk.
- **Entry:** Settings → "Edit bridge policy.yaml".
- **DS components:** `PolicyEditorBridgeScreen` / `PolicyEditorView`, Safe-presets card
  (Cautious / Balanced / Bypass), monospace YAML editor, "Reload policy on bridge" action.
- **States captured:** disconnected (shows the balanced-preset YAML; save is gated on a live SSH session).
- **Shots:** `17-policy-editor-{dark,light}.png`. *(Real-app)*

### 18 · Connect host (password sheet)
- **Job:** authenticate to a saved host to start a session.
- **Entry:** Fleet → tap a saved host row.
- **DS components:** "Connect" sheet header, host card (`PixelAvatar` + `user@host:port`), secure password
  field, Connect button.
- **States:** populated (host card + empty password).
- **Shots:** `18-connect-host-{dark,light}.png`. *(Real-app)*

### 19 · Add host
- **Job:** add a BYO SSH host by pasting an `ssh` command, or pick Lancer Cloud; advanced auth/tmux/startup.
- **Entry:** Fleet empty-state "Connect a host"; post-onboarding.
- **DS components:** `AddHostView`, `DSScreenHeader` ("add host_"), "bring your own / lancer cloud"
  segmented toggle, `$ ssh user@host -p 2222` paste field, "advanced (auth · tmux · startup)" disclosure,
  "connect & save" button.
- **States:** populated (blank form).
- **Shots:** `19-add-host-{dark,light}.png`. *(Real-app)*

### 20–23 · Orb / SSH connect overlay states
- **Job:** the animated connection overlay shown while establishing/holding an SSH session.
- **Entry:** during connect from Fleet / a saved host.
- **DS components:** `SSHConnectOverlay`, animated orb, phase messaging.
- **States captured:** connecting (`20`), connected (`21`), slow/still-trying (`23`), failed with a typed
  error (`22`, "Can't find host …").
- **Shots:** `20-orb-connecting-{dark,light}.png`, `21-orb-connected-{dark,light}.png`,
  `22-orb-failed-error-{dark,light}.png`, `23-orb-slow-{dark,light}.png`. *(Gallery: `orb-*`)*

### 30 · Diff viewer
- **Job:** review a unified diff an agent proposes before approving a file write.
- **Entry:** approval card → EDIT&RUN / diff preview; Pro partial-hunk review.
- **DS components:** `DiffView`, `DSDiffChips`, add/remove gutters, monospace hunks.
- **States:** populated.
- **Shots:** `30-diff-viewer-populated-{dark,light}.png`. *(Gallery: `diff`)*

### 31 · File preview
- **Job:** read a file's contents (e.g. before an MCP read, or browsing via SFTP).
- **Entry:** MCP read approval; file browser.
- **DS components:** `FilePreviewView`, syntax-tinted monospace, filename header.
- **States:** populated (a Swift source file).
- **Shots:** `31-filepreview-populated-{dark,light}.png`. *(Gallery: `filepreview`)*

### 40 · Blocks terminal (static mock)
- **Job:** the Warp-style block transcript design reference — command blocks with exit chips, a streaming
  block, and a status line — without a live SSH connection.
- **Entry:** design reference; the live version is page 42.
- **DS components:** `ChatTranscriptView`/`ToolCardView` over `DSBlockCard` (left state gutter,
  `DSPromptLine`, `DSExitChip`), status header with "1 pending / Streaming".
- **States:** populated (mock transcript).
- **Shots:** `40-blocks-terminal-{dark,light}.png`. *(Gallery: `blocks`)*

### 41 · Chat / transcript gallery
- **Job:** the conversational block transcript components catalog.
- **Entry:** design reference.
- **DS components:** chat bubbles + tool cards over `BlockRenderer` mocks.
- **States:** populated.
- **Shots:** `41-chat-{dark,light}.png`. *(Gallery: `chat`)*

### 42 · LIVE SSH session terminal ★
- **Job:** the **real** unified-PTY block pipeline — a command runs over a live SSH connection and forms
  a Warp-style block with real output and a real exit code. This is the shipping terminal, not a mock.
- **Entry:** Fleet → connect a host → session.
- **DS components:** live `BlockRenderer` blocks (`RUN › COMMAND` header, real stdout, `✓ exit 0` chip),
  `$ command` input bar, keyboard rail (Esc / Tab / Ctrl / Tmux + history).
- **States:** populated (a live `echo && ls && git status` block against localhost sshd).
- **Shots:** `42-live-session-{dark,light}.png`. *(Gallery: `session`, real SSH to localhost)*

### 50 · Agent HUD
- **Job:** the per-agent state HUD component (thinking / streaming / approval / done / error / offline).
- **Entry:** design reference (`PixelBox` states).
- **DS components:** `AgentHUDGalleryScreen`, `PixelBox`.
- **States:** all HUD states on one canvas.
- **Shots:** `50-agent-hud-{dark,light}.png`. *(Gallery: `hud`)*

### 51 · Agent status header
- **Job:** the connected-session status header component.
- **Entry:** design reference.
- **DS components:** `AgentStatusHeaderGalleryScreen`.
- **States:** populated.
- **Shots:** `51-status-header-{dark,light}.png`. *(Gallery: `statusheader`)*

### 52 · Keyboard rail
- **Job:** the terminal accessory key rail (Esc/Tab/Ctrl/arrows/Tmux) shown above the soft keyboard.
- **Entry:** live session input.
- **DS components:** `KeyboardGalleryScreen`, key-rail buttons.
- **States:** populated.
- **Shots:** `52-keyboard-rail-{dark,light}.png`. *(Gallery: `keyboard`)*

### 53 · Features overview
- **Job:** internal catalog of the four prototyped features (shortcut bar, media attach, typed inbox, APNs).
- **Entry:** design reference.
- **DS components:** `FeaturesGalleryScreen`.
- **States:** populated.
- **Shots:** `53-features-overview-{dark,light}.png`. *(Gallery: `features`)*

### 54 · States gallery (loading / offline / error)
- **Job:** the cross-cutting state components — offline banner, skeleton loaders, typed error cards.
- **Entry:** design reference.
- **DS components:** `DSOfflineState`, `DSSkeletonList`, `DSTypedErrorCard` (auth / network / host-key /
  DNS), `DSSlowOverlay`.
- **States:** all error/loading states on one canvas.
- **Shots:** `54-states-gallery-{dark,light}.png`. *(Gallery: `states`)*

### 60 · Component catalog
- **Job:** the full design-system component library — buttons, quote blocks, links, diff chips, pixel
  art, cards. The canonical visual reference.
- **Entry:** design reference.
- **DS components:** every `DesignSystem/Components/*`.
- **States:** populated catalog.
- **Shots:** `60-component-catalog-{dark,light}.png`. *(Gallery: `components`)*

---

## Couldn't capture (and why)

- **Activity feed — populated.** The "while you were away" audit list only fills from a live
  `agent.audit.tail` over an SSH session with real audit history; the seeded DB has none, so only the
  not-connected empty state is shown. The component itself (mono audit rows) is exercised by the
  `BridgeAuditFeedView`; a populated capture needs a live daemon with logged events.
- **SSH Keys — populated.** Keys are Secure-Enclave-backed and generated on-device; they can't be
  seeded externally, so only the "no keys yet" state is captured.
- **Cloud Agents / runs (Library → Agents).** Entirely gated behind a paid Lancer Cloud entitlement
  (`PurchaseManager.cloudEntitlement`), which isn't active in the simulator. The category card shows the
  locked "Lancer Cloud" affordance (captured in page 14); the inner `AgentsView`/`AgentRunDetailView`
  need a live entitlement + backend.

---

## Known design debt (deferred from the pixel-perfect polish plan)

`docs/superpowers/specs/2026-06-12-lancer-pixel-perfect-polish-plan.md`. **Batches 1–3 are DONE**
(header unification across the 4 tabs, DS empty states, Activity mono fonts, Settings section
typography/padding, Fleet stat labels, Billing DS header + card chrome, MCP-card 44pt touch targets,
paywall surfaces — all built and verified in light+dark). Only two items remain **deferred**:

1. **P1-12 — global `DSButton` 44pt minimum height.** A handful of secondary/ghost buttons fall just
   under the 44pt iOS touch-target minimum. Deferred because it's a global token change and must be
   done carefully to avoid regressing every button's vertical rhythm at once.
2. **P1-14 — onboarding / Connect-sheet `DSScreenHeader` unification.** The onboarding hero and the
   Connect password sheet (page 18) still use ad-hoc headers rather than the flush `DSScreenHeader`
   geometry used by the four main tabs. Cosmetic header-alignment debt; visible if you compare the
   `_`-cursor prompt headers (Inbox/Fleet) against the Connect sheet's plain "Connect" title.

Neither blocks shipping; both are fine-tuning. Everything else from the plan is landed.
