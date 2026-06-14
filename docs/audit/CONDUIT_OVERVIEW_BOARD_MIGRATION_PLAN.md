# Conduit — "Overview Board" UI Migration Plan

**Date:** 2026-06-13
**Target design:** `Conduit Overview Board.html` (+ `cc-*.jsx`, `conduit.css`) in the design handoff
**Status:** Plan for approval. No app code changed yet.
**Decisions locked (from review):** square corners (subtle 0–2px) · keep Chakra Petch + Fira Code · include Dispatch + bridge onboarding now (grounded to real infra) · **dissolve Library**.

---

## 0. Premise

This is a **visual-language refresh + card/IA redesign**, not a rebuild. The app is already
~85% of the board at the token level: electric-blue accent (`#2f43ff` ≈ board `#3d5bff`),
dark-first, spectrum bar, pixel avatars, lowercase mono `DSScreenHeader`, four tabs
(inbox/fleet/activity/settings), a cross-vendor spend Fleet, a "while you were away" Activity,
and a live `DaemonChannel.dispatchAgent` RPC. We refine, we do not start over.

The board and `FRONTEND_SIMPLIFICATION_REVIEW_UPDATE.md` disagree (board = expansion/control-plane;
doc = contraction/approvals-only). Reconciliation adopted here:

- **Design-system refinements from the board → adopt wholesale** (low risk, clear wins).
- **New product surfaces (Dispatch, bridge onboarding) → build now but grounded to real infra,**
  not the board's aspirational copy.
- **Library → dissolve** (simplicity-first; both the user and the decision doc agree).

---

## 1. Design tokens (`DesignSystem/Tokens.swift`)

### 1.1 Decouple risk from brand — the headline change
Today `risk(2)` returns `accent` (electric blue) → risk collides with the CTA color. Fix:

- Add an **independent 4-step risk ramp** + soft/border variants:
  - `riskLow` green `#3fb57e` · `riskMed` amber `#e0a33a` · `riskHigh` **orange `#f07a2e`** (new step) · `riskCrit` red `#f24b3d`
- Rewrite `risk(_ level:)` / `riskSoft(_:)` to map `0→low 1→med 2→high 3→crit` and **never return `accent`**.
- Reserve `accent` for brand + primary CTA only.
- Keep the spectrum colors and electric blue as-is.

### 1.2 Corners — keep square
Per decision: keep `r1=r3=r4=0` (and `r2=2` chips). **Do not** adopt the board's 7–12px rounding.
Sheets stay at `r5=4`. This preserves the BLOCKS identity.

### 1.3 Fonts — keep
No change. Chakra Petch (display) + Fira Code (mono). The board's IBM Plex is a browser default,
not a target.

**Risk:** §1.1 is a global change — `risk()` feeds command gutters, chips, `PixelBox` state colors,
banners. Requires a full call-site audit + before/after gallery screenshots (light **and** dark) +
WCAG contrast check on the new orange and soft-bg text.

---

## 2. Reusable components — create / update / remove

### Create
| Component | Purpose | Backed by |
|---|---|---|
| `DSDecisionSheet` | Full-detail approval bottom sheet: command + diff + blast radius + plain-language "why this asks you" (matched rule) + **Face ID gate** for critical + all 4 actions. | `BiometricGate`, `Approval`, `DiffView`, `ApprovalBlastRadius` |
| `DSStatusHeader` | Calm per-tab strip: `● bridge connected · policy: balanced · today $4.94`. Distinct from the live-session `AgentStatusHeader`. | `FleetStore` / bridge status |
| `DSSpendHero` | Fleet header: big `$` today, per-vendor breakdown bar, runs + concurrency + cap. | `FleetSummary` |
| `DispatchView` | New screen — compose a task for an agent (see §5). | `BridgeSessionActions.dispatch` |

### Update
| Component | Change |
|---|---|
| `Tokens.swift` | §1.1 risk ramp. |
| `InboxCards.swift` (`DSMCPCallCard`, `DSAskQuestionCard`) | Re-rank actions: primary **`Deny`** (red-outline) / **`Approve`** (blue-filled) pair at opposed ends; demote **`Edit & run`** / **`Allow always…`** to a quiet link row beneath. Tapping the card body opens `DSDecisionSheet`. Inline blast chips. |
| `DSBlastRadiusBanner` | Add **files-count** + **credentials** chips; expose a compact inline variant for the card. |
| `DSButton` | Add a `quiet`/`link` variant for demoted secondary actions. |
| `FleetView` | Swap summary card → `DSSpendHero`; add a "Codex is waiting" attention banner; header trailing `+ task` → `DispatchView`. |
| `ActivityView` / `BridgeAuditFeedView` | Restyle rows with action-type chips: auto-allow / auto-deny / escalate / you-allow / dispatch. |
| `SettingsView` | Regroup: bridge & hosts / approvals (policy, notifications) / security (Face ID, redact, audit, **SSH keys**) / account (Pro, billing). Add **Trust & Privacy**. Remove Library folder-icon. |
| `PolicyEditorView` | Restyle: preset segmented (cautious/balanced/bypass via `DSAutonomyPresetBar`) + rules with allow/ask/deny effect chips + "unmatched → asks (fail-safe)" note. |
| `OnboardingView` | Keep headline `agents ask. you approve. work resumes.`; anchor CTA low; bridge-install copy over the working SSH path (§6). |

### Remove
| Target | Why |
|---|---|
| `SessionShellView` + `SessionSurface` | Dead code; carries a wrong Diff/Inbox Pro-gate. |
| `mockHostCounts` (`LibrarySupportViews.swift`) | Fake data in a security app. Ship-blocker. |
| `LibraryView` from production nav + Settings folder-icon + `SettingsWithLibraryView` Library injection | Library dissolved. |
| Standalone snippet run/new surfaces from nav | Snippets stay in-session only. |

---

## 3. Keep as-is (already on-spec)
`SpectrumBar` · `PixelAvatar` / `PixelBox` · `DSScreenHeader` · `DSAutonomyPresetBar` · fonts ·
`SessionView` block terminal · TOFU host-key trust · `DiffView` (free; only partial-hunk apply is Pro).

---

## 4. Screen mapping (current → board)

| Current | Board target | Work | Keep / Simplify / Redesign / Remove |
|---|---|---|---|
| `InboxView` | Inbox + decision sheet + first-run checklist + demo approval | card restyle + sheet + empty-state modes | **Redesign** (card hierarchy + sheet) |
| `FleetView` | Spend hero + per-vendor bar + waiting banner + `+ task` | enhance summary → hero | **Redesign** (keep glanceable, not busy) |
| `ActivityView` | Action-type-chipped audit | row restyle | **Simplify** |
| `SettingsView` | Cleaned groups + Trust & Privacy, no Library | regroup + promote privacy copy | **Redesign** |
| `OnboardingView` | Keep headline; CTA low; bridge copy | restyle | **Simplify** |
| `PolicyEditorView` | Preset + effect chips + fail-safe | restyle | **Simplify** |
| `SessionView` | unchanged | none | **Keep** |
| *(new)* `DispatchView` | compose a task | new screen → `dispatch` RPC | **Create** |
| `LibraryView`, `SessionShellView` | gone | delete/gate | **Remove** |

---

## 5. Dispatch (included now — grounded)

**Backend exists.** `DaemonChannel.dispatchAgent(agent:cwd:prompt:budgetUSD:)` → `agent.dispatch`
→ `DispatchResult`, surfaced via `BridgeSessionActions.dispatch`, already wired in `AppRoot.swift:624`.

**Frontend (`DispatchView`):** pushed screen, BLOCKS-native, square, our fonts:
`DSScreenHeader("dispatch", breadcrumb: "start a task")` → agent picker (radio rows, non-offline) →
working-dir mono input (prefilled from agent cwd) → multiline task field → optional daily-budget
`$` input → square accent **"Dispatch task"** (disabled until task non-empty).

**Entry points (iOS-native, no floating FAB):** Fleet header trailing **`+ task`** action; secondary
CTA on the Inbox empty state.

**Wiring:** widen `BridgeSessionActions.dispatch` to pass the optional budget (the RPC already
accepts `budgetUSD`). On success → toast + the new run appears in Fleet/Activity; its gates arrive
as Inbox cards. **Relationship to terminal:** Dispatch starts the loop; Inbox governs it; Activity
audits it; `SessionView` is the manual-override / live drill-in (see review §"Dispatch vs terminal").

---

## 6. Bridge onboarding (honest version)

**Reality (corrected after codebase study):** `DaemonBootstrap.ensureInstalled()` (download + SHA-256
verify + install) **exists but is never called.** Today `DaemonChannel.start()` assumes `conduitd` is
**already present** at `$HOME/.conduit/bin/conduitd`. So the bridge is neither auto-installed over SSH
*nor* installed via `curl|sh` — it's assumed pre-installed. The board's manual `curl conduit.dev/install
| sh` + QR-pair flow also needs infra that does not exist (public installer endpoint + phone-side
pairing UX; `PairingCrypto` exists but is unwired to onboarding). **This is a real infra gap, not just a
copy choice.**

**Plan:**
- **Now:** keep SSH-paste as the working path; simplify the current **7-step** onboarding toward the
  board's ~4 (hero → connect host → caution preset). Adopt the board's *copy/visual* — "Connecting
  installs the bridge (conduitd) that enforces your policy and survives disconnects."
- **Infra track (separate, gated, sequenced):** (1) **wire `DaemonBootstrap.ensureInstalled()` into the
  connect flow** so connecting actually installs/repairs `conduitd` over SSH (today it's assumed
  pre-installed — this is the gap that makes the bridge story true); (2) publish `conduit.dev/install`;
  (3) wire `PairingCrypto` to a QR-pair onboarding screen. Surface the manual-install path only after
  (1)–(3). **Do not block the design migration on this.**

> Onboarding currently ships **7 steps** (hero, how-it-works, SSH setup, notifications, Face ID, coach,
> compute) — the board's 4-step flow is a welcome simplification; fold notifications/Face-ID/coach into
> contextual prompts (HIG: defer non-essential setup) rather than dedicated first-run slides.

---

## 7. Architecture changes
Mostly view-layer. Structural items:
1. Card tap → `DSDecisionSheet` presentation (Inbox routing).
2. Per-tab `DSStatusHeader` data source (reuse `FleetStore` / bridge status).
3. Demo-approval local state in `InboxViewModel` (+ dismissal flag).
4. `BridgeSessionActions.dispatch` widened for budget; `DispatchView` navigation.
5. Library removal: drop `onOpenLibrary` plumbing, `SettingsWithLibraryView`, Settings folder-icon.

No persistence/schema changes. No SSH/terminal pipeline changes.

---

## 8. Phasing & sequencing

- **Phase 0 — credibility cleanup:** delete `SessionShellView`/`SessionSurface`, `mockHostCounts`,
  dissolve Library (hub + folder-icon + nav), de-Library Add Host copy. Build green.
- **Phase 1 — design system:** risk-ramp tokens + `risk()` rewrite; `DSDecisionSheet`,
  `DSStatusHeader`, `DSButton` quiet variant; approval-card re-rank + inline blast chips.
- **Phase 2 — screen restyles:** Fleet (`DSSpendHero` + `+ task`), Activity chips, Settings regroup +
  Trust & Privacy + Security/SSH-keys, Policy restyle, Onboarding restyle.
- **Phase 3 — activation + dispatch:** demo approval, first-run checklist, `DispatchView` wired to RPC.
- **Phase 4 — QA:** every `DebugGalleryView` route, light **and** dark, contrast + Dynamic Type +
  VoiceOver (hide decorative cursor), tap targets ≥44pt; re-shoot App Store screenshots.
- **Phase B (separate, infra-gated):** manual bridge install + QR-pair onboarding.

**Build loop:** `cd Packages/ConduitKit && swift build` after each change; XcodeBuildMCP
`build_sim` for the full app target at phase boundaries (catches strict-concurrency breaks SPM misses).

---

## 9. HIG / accessibility guardrails
- Tap targets ≥44pt (cards already 44; board 46 — keep ≥44).
- Decorative blinking cursor → hidden from accessibility.
- Mono at 10–11px must pass Dynamic Type (keep `relativeTo:` scaling).
- Destructive `Deny` = red, primary `Approve` = blue-filled (distinct, per HIG).
- Bottom sheets via `.presentationDetents`; biometric gate for critical via `BiometricGate`.
- No floating FAB (use nav/header actions).
- Never imply Conduit Cloud is required for BYO-host approvals.

### 9.1 HIG study — additions folded in (verbatim Apple HIG, June 2026)
- **Mono text sizing:** iOS min 11pt / default 17pt. Reserve 10–13px mono for **terminal output and
  metadata**, not primary copy — size up card titles/leads and guarantee Dynamic Type + Bold Text on the
  custom faces. (HIG *Typography*.)
- **Risk ramp ≠ color alone:** every risk level must carry a **label/glyph** (LOW/HIGH), not just hue —
  our `RiskChip` already prints the word; keep it. WCAG AA: 4.5:1 text, 3:1 non-text chips on near-black.
  (HIG *Accessibility*.)
- **Decision sheet detents:** open `.medium` (summary) → drag `.large` (full diff/command), grabber
  visible. For **critical**, `interactiveDismissDisabled` or confirm-on-swipe so an accidental swipe
  can't dismiss a critical decision. (HIG *Sheets*.)
- **Face ID:** `LAContext.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics)` with **passcode
  fallback** (`.deviceOwnerAuthentication`); don't prompt at launch. (HIG *Privacy* + LocalAuthentication.)
- **Dispatch entry = nav-bar `ToolbarItem(.primaryAction)` `+`**, never a tab and never a FAB ("a tab
  bar supports navigation, not actions"). Disable the CTA when no bridge slot is connected.
- **Notifications:** pending approvals → `.timeSensitive` interruption level (breaks through Focus); an
  in-progress Dispatch run → **Live Activity / Dynamic Island** (≤8h, end immediately on completion, no
  sensitive content on Lock Screen). Never `.critical` (entitlement-gated). (HIG *Notifications* /
  *Live Activities*.)
- **iPad/landscape:** `TabViewStyle.sidebarAdaptable` promotes the tab bar to a sidebar.
- **Reduce Motion** (calm the blinking cursor + PixelBox; fade not slide) and **Reduce Transparency**
  (solid surfaces instead of blur on terminal/sheets); haptics sparingly (light on Approve, heavier on
  Deny). Mark decorative pixel art + cursor `accessibilityHidden(true)`.

### 9.2 Codebase study — corrections folded in
- **Bridge install is unwired** (§6 corrected): `DaemonBootstrap.ensureInstalled()` exists but is never
  called; `conduitd` is assumed pre-installed. Wiring it is the first infra-track task.
- **Library dissolution = flatten, not delete the nav host:** `SettingsWithLibraryView` wrapper stays
  but drops the Library `navigationDestination`/`onOpenLibrary`; the snippets/keys/agents **grid** is
  what's removed. Keys → Settings·Security; snippets → in-session; standalone `SnippetsLibraryView`
  (only reachable via Library today) is intentionally dropped.
- **Deleting `SessionShellView` is safe:** Diff stays reachable from `InboxView` (free path); the dead
  shell's Pro-gated Files/Preview/Diff entry points are redundant.
- **Strict concurrency:** `InboxViewModel` vs `LiveInboxViewModel` are swapped in `AppRoot` — both must
  stay `@MainActor @Observable` with identical `approvals` visibility. Verify at Phase 1.
