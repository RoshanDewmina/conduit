# Conduit — UI Migration Handoff (Overview Board)

**Date:** 2026-06-14
**Branch:** `codex/uiux-audit` (base branch for PRs is `master`)
**Author of this pass:** Claude (Opus 4.8), session continuing the Overview Board migration
**Purpose:** Hand off the in-flight "Overview Board" UI migration to another agent with **everything**
needed to continue: what was done, what remains, how to build/test, how the visual harness works,
environment/macOS-beta gotchas, the subagent orchestration method, and open security items.

> **Read these first (in order):**
> 1. This file (orientation + status + how-to).
> 2. `docs/audit/CONDUIT_OVERVIEW_BOARD_MIGRATION_PLAN.md` — the approved plan; §8 has live phase status.
> 3. `docs/audit/CONDUIT_UI_CONSISTENCY_RULES.md` — **binding** design rules (R1–R8). Every screen obeys these.
> 4. `docs/audit/LAUNCH_SCOPE_LEDGER.md` — what ships v1 vs defer vs cut; bug ledger §D; launch gate §E.
> 5. `CLAUDE.md` (repo root) — MCP tooling + build/visual-verification workflow (authoritative).

---

## 0. TL;DR — current state

- **The migration is ~Phases 0–3 done and in-sim verified.** ConduitKit (`swift build`) **and** the full
  Xcode app target (`build_sim`) are **green**. Working tree is **clean**; all work is committed on
  `codex/uiux-audit`. **Nothing is pushed and no PR is open** (commit/push only on explicit request).
- **Not yet done:** wire `DSDecisionSheet` to card-tap; demo-approval + first-run checklist (Phase 3
  remainder); the Phase-4 accessibility/Dynamic-Type/VoiceOver sweep + re-shoot App Store screenshots;
  Phase B (infra-gated bridge install + QR pairing). One **MEDIUM security follow-up** (SSH-keys
  biometric gate) — see §9.
- **Everything that's connection-dependent** (live Policy rules list, live Activity audit rows, live
  Dispatch run) was verified at the **component/tone** level in the simulator because the audit sim has
  no live SSH bridge. They need a real connected host to verify with live data.

---

## 1. What Conduit is (orientation)

Conduit is an **iOS SSH / AI-agent management app**. The product thesis: coding agents (Claude Code,
Codex, opencode, …) running on your machines **pause for risky actions**; Conduit relays the approval
to your phone; you approve/deny; the agent resumes. It is a **mobile control plane for agent loops**,
not just notifications.

- **UI:** 100% SwiftUI, **Swift 6** (strict concurrency on). No web renderer — the only way to see UI is
  the **iOS Simulator**.
- **Package:** `Packages/ConduitKit` (SPM, ~100 files) holds all UI + most logic, split into modules
  (`AppFeature`, `InboxFeature`, `SettingsFeature`, `OnboardingFeature`, `SessionFeature`,
  `WorkspacesFeature`, `KeysFeature`, `DesignSystem`, `ConduitCore`, `AgentKit`, `SSHTransport`,
  `SecurityKit`, `PersistenceKit`, `NotificationsKit`, `TerminalEngine`, …). The Xcode app target
  (`Conduit.xcodeproj`, scheme `Conduit`) wraps it.
- **Backend bridge:** a Go daemon `conduitd` (`daemon/`) installed on the user's host enforces policy
  and speaks to the app over SSH (`DaemonChannel`) + APNs. Live loop is **proven E2E** (see memory
  `project_live_loop_e2e`).
- **Design language = "BLOCKS":** dark-first, **square corners** (radius 0–2px; sheets r5=4), mono +
  display fonts (Fira Code + Chakra Petch), electric-blue accent **`#2f43ff` used for CTAs only**,
  a red→blue "spectrum" strip for data series, pixel-art avatars/`PixelBox` state art.

---

## 2. The design contract (must-obey rules)

Full text: `docs/audit/CONDUIT_UI_CONSISTENCY_RULES.md`. The ones that drive most decisions:

- **R1.1 / R1.2** — A bottom-pinned CTA sits on a **solid footer bar** (1px top hairline + safe-area
  padding), **never a `LinearGradient`** (the gradient bled over scroll content and clipped the last
  element — this was the user-reported "bypass button clipped" bug). Scroll content must fully clear it.
- **R1.3** — Horizontal gutter is **always 18pt**. No per-screen gutters.
- **R1.4** — Tab roots use `DSStatusHeader`/`DSScreenHeader`; pushed screens use a SubNav (back chevron +
  lowercase mono title). Never mix.
- **R2** — Spacing scale is **only** `4·6·8·10·12·14·16·18·22·24·28`. No one-off margins.
- **R3.1–R3.4** — Button rows equal-width; labels short enough to never wrap at 320pt; **decision order
  is fixed: destructive (Deny) LEFT outline, affirmative (Approve) RIGHT filled**; secondaries go on a
  **second row** (never inline with the one-tap row). Heights: primary 52, in-row 46, quiet 40.
- **R5 (the headline color law):**
  - **R5.1** — brand blue `#2f43ff` is **CTA-only**; never risk/state/data.
  - **R5.2** — risk ramp is **independent + monotonic**: green → amber → orange → red, and **always
    paired with a text label** (a11y), never color alone.
  - **R5.3** — data series (spend/quota bars) use the **brand spectrum red→blue**, not vendor hues.
  - **R5.4** — privacy-positive / "stays on host" = green, consistently.
- **R6** — One canonical spring for sheets; haptics: Approve `.success`, Deny `.warning`, destructive
  confirm `.impact(.heavy)`, selection/segment/radio `.selection`. Respect Reduce Motion.
- **R7.2** — Tapping any file reference opens the **full file in a bottom drawer** (header
  filename·path·line-count·read-only + line-numbered mono body + Copy/dismiss). One canonical file view.

**Design tokens** live in `Packages/ConduitKit/Sources/DesignSystem/Tokens.swift`:
- `@Environment(\.conduitTokens) private var t` in every view.
- `t.accent` = brand CTA blue. `t.risk(level)` / `t.riskSoft(level)` = the 0→green 1→amber 2→orange
  3→red ramp (independent of accent — this was a pervasive bug, now fixed: see §3).
- `ConduitTokens.spectrumColors` = the red→blue strip; `SpectrumBar` is the animated decorative version.
- `DSChipTone` enum: `.ok .warn .orange .danger .accent .info .neutral`. `DSStatusDotTone` mirrors it.
- Fonts: `.dsMonoPt(size, weight:)`, `.dsSansPt(size, weight:)`, `.dsDisplayPt(size, weight:)`.

---

## 3. What was done THIS session (commit-by-commit)

All on `codex/uiux-audit`. Newest last:

| SHA | Title | What's in it |
|---|---|---|
| `06fbe3cd` | design(ios): migrate design system + screens toward Overview Board | Prior-session work committed: **risk-ramp decoupled from brand across 7 files** (added `riskOrange #E2662C`, `DSChipTone.orange`, `DSStatusDotTone.orange`; rewired `risk(2)` away from `accent`); canonical **file-viewer drawer** (`FilePreviewView` R7.2) wired into `AgentFilesView`; **billing spend hero** + spectrum strip; plus all audit/plan docs + board exports + screen captures. |
| `cc48d69b` | chore: branch sync | Non-UI branch changes carried along: push-backend `relay_security` + tests, App Store metadata, fastlane copy, Next.js prototype, WS-5 cloudrun notes. |
| `62e4b94a` | **Wave 1** — credibility cleanup + design-system foundations | **Phase 0:** deleted `SessionShellView`/`SessionSurface` (dead, wrong Pro-gate); removed `mockHostCounts` (fake host data) + dead `SnippetsLibraryView`; dissolved **Library** (deleted `LibraryView`, dropped nav destination + `onOpenLibrary` plumbing + Settings folder-icon; **kept** `SettingsWithLibraryView` wrapper); de-Library key copy → "Settings › Security". **Phase 1:** `DSButton` `quiet` variant; re-ranked approval cards `DSMCPCallCard` (InboxCards) **and** `DSApprovalCard` (ChatComponents) to R3.3 (Deny-left/Approve-right + quiet second row + inline risk chips); `DSBlastRadiusBanner` files/credentials chips + new `DSBlastRadiusInline`; **3 new components**: `DSStatusHeader`, `DSSpendHero`, `DSDecisionSheet`. |
| `55b15981` | **Wave 2** — restyle 6 screens | `FleetView` → `DSSpendHero` + waiting-banner + `+ task` header action (`onNewTask`, defaulted); `ActivityView`/`BridgeAuditFeedView` → action-type chips; `SettingsView` → regrouped (Bridge&Hosts / Approvals / Security / Account) + new inline `TrustPrivacyView` (R5.4 green); `PolicyEditorView` → `DSAutonomyPresetBar` + per-rule effect chips + fail-safe note (raw YAML editor kept); `OnboardingView` → 7→4 steps + **solid-footer CTA fixes the clipped-bypass bug**; new `DispatchView`. **Also fixed** `OnboardingView` missing `import ConduitCore` (caught by app target, not SPM). |
| `bd01e164` | feat(ios): wire DispatchView → agent.dispatch | Fleet `+ task` presents `DispatchView`; agent list built from connected fleet slots (id = `slotUUID|vendor`); `onDispatch` routes to the right `DaemonChannel.dispatchAgent` with optional budget. |
| `924c040f` | feat(ios): SSH keys under Settings · Security | Threaded SSH `KeyStore` (`env.keyStore`) through `SettingsWithLibraryView` → `SettingsView` (optional, defaulted) + added "SSH keys" nav row pushing the real `KeysView`. ⚠️ **triggered a security finding — see §9.** |
| `2ae0b4b9` | docs(migration): mark phases 0–3 done | Updated plan §8 with live status + open items. |

**New components created (files):**
- `DesignSystem/Components/DSStatusHeader.swift` — `DSStatusHeader(connected:policy:todaySpend:)` per-tab strip.
- `DesignSystem/Components/DSSpendHero.swift` — `DSSpendHero(todayUSD:vendors:runs:concurrent:capUSD:)` Fleet hero + spectrum vendor bar.
- `DesignSystem/Components/DSDecisionSheet.swift` — `DSDecisionSheet(risk:agentName:action:command:whyText:requiresBiometric:diff:blastRadius:onDeny:onApprove:onEditAndRun:onAllowAlways:)` full approval bottom-sheet **(built but not yet presented — see §6 TODO #1)**.
- `AppFeature/DispatchView.swift` — `DispatchView(agents:[DispatchAgent], onDispatch:)`; `DispatchAgent(id:name:cwd:isOffline:)`.

**Files deleted:** `AppFeature/SessionShellView.swift`, `AppFeature/LibraryView.swift`.

---

## 4. Verified vs. unverified (be honest with the user)

**Visually verified in-sim, light AND dark, on the real app (not just gallery):**
- Inbox approval cards: two-row R3.3 layout; HIGH=orange / MED=amber chips; APPROVE only blue.
- Fleet: `DSSpendHero` ($0.00 honest empty), spectrum strip, `+ task` → Dispatch sheet.
- Dispatch: SubNav header, agent/cwd/task/budget fields, solid-footer CTA (disabled until valid).
- Settings: 4-section regroup; SECURITY shows **SSH keys** row → real `KeysView` (no-keys empty state).
- Trust & Privacy: "STAYS ON YOUR HOST" items green, "CROSSES THE WIRE" neutral (R5.4).
- Onboarding: hero headline preserved; **solid footer CTA** on hero + connect step (R1.1 fixed).
- File-viewer drawer + risk chips (component catalog) from prior pass.

**Built + compiles, but NOT yet verified with live data (needs a connected SSH host):**
- Policy rules list (`PolicyEditorView`) — populates from live `policy.yaml`.
- Activity audit rows (`BridgeAuditFeedView`) — populate from `agent.audit.tail`.
- A real Dispatch run round-trip (sheet → RPC → run appears in Fleet/Activity → gate as Inbox card).

To verify those, connect a real host (see §7's live-session harness) and re-screenshot.

---

## 5. How to BUILD (the inner loop + the catch-all)

**Two build paths — use both:**

1. **ConduitKit-only inner loop (fast, ~2–6s):**
   ```bash
   cd /Users/roshansilva/Documents/command-center/Packages/ConduitKit && swift build
   ```
   Use after every edit. **Caveat:** SPM does NOT catch all strict-concurrency / module-visibility
   breaks. Example this session: `OnboardingView` referenced `AutonomyPreset` (in `ConduitCore`) without
   importing it — **SPM passed, the app target failed.** So:

2. **Full app target (catches what SPM misses) — via XcodeBuildMCP, at phase boundaries:**
   - First call of a session: `mcp__XcodeBuildMCP__session_show_defaults` to confirm project/scheme/sim.
   - Then `mcp__XcodeBuildMCP__build_sim` (empty args — defaults are set).
   - It returns structured JSON with precise `file:line` errors. **A clean `swift build` is necessary
     but not sufficient — always run `build_sim` before declaring a phase done.**

**Trick to force-recompile after edits** (SPM can under-report when timestamps look cached):
```bash
cd Packages/ConduitKit && touch Sources/<EditedModule>/<File>.swift && swift build
```

**MCP tooling (prefer over raw shell — see `CLAUDE.md` for the full table):**
- `XcodeBuildMCP` (`mcp__XcodeBuildMCP__*`) — build/run/test app target, sim lifecycle, screenshots, UI
  automation, coverage. Headless (no Xcode needed).
- `xcode` (`mcp__xcode__*`) — needs Xcode.app open; live diagnostics, SwiftUI `RenderPreview`, REPL.
- `apple-docs` — **use before guessing any Apple API.**
- `context7` — **use before guessing any third-party API** (SwiftNIO, swift-crypto, Citadel/SSH).
- `ios-simulator` (`mcp__ios-simulator__*`) — UI automation by a11y tree (tap/swipe/describe).

---

## 6. What REMAINS (prioritized TODO for the next agent)

1. **[security, do first] SSH-keys biometric gate** — see §9. MEDIUM finding from automated review.
2. **Wire `DSDecisionSheet` to card-tap (Phase 1 leftover).** The component exists; Inbox cards still use
   inline actions. Plan §7.1: tapping a card body should present `DSDecisionSheet` via `.sheet` with
   `.presentationDetents([.medium,.large])` + grabber; for **critical**, gate Approve with `BiometricGate`
   and consider `interactiveDismissDisabled`. Routing lives in `InboxFeature/InboxView.swift`
   (`pendingCard(_:)`). The sheet needs the matched-rule "why" text + blast radius — both already on
   `Approval`/`ApprovalBlastRadius`.
3. **Phase 3 remainder:** demo-approval local state in `InboxViewModel` (+ dismissal flag) and the
   first-run inbox checklist (board's empty-state modes). Pure local state; no backend.
4. **Verify connection-dependent screens with live data** (§4) — connect a real host, re-screenshot
   Policy + Activity + a full Dispatch round-trip.
5. **Phase 4 QA sweep:** WCAG contrast on the new orange + soft-bg text; Dynamic Type at large sizes
   (mono 10–11px must scale via `relativeTo:`); VoiceOver (mark decorative cursor/PixelBox
   `accessibilityHidden(true)`); tap targets ≥44pt; then **re-shoot App Store screenshots**
   (`fastlane/metadata/`, `docs/app-store-metadata.md`).
6. **Phase B (infra-gated, do NOT block UI on this):** wire `DaemonBootstrap.ensureInstalled()` into the
   connect flow (today `conduitd` is **assumed pre-installed** — real infra gap), publish
   `conduit.dev/install`, wire `PairingCrypto` to a QR-pair onboarding screen. See plan §6.
7. **Ledger bug D2:** `agent_status_opencode.go` reads the wrong config path
   (`~/.local/share/opencode/...` vs `~/.config/opencode/opencode.json`) — one-line fix; makes opencode
   stop reporting logged-out. (Backend, not UI.)

---

## 7. How to TEST visually (the simulator harness)

**Simulator:** iPhone 17 Pro, **udid `095F8B3A-FEA3-4031-A2A5-561755740730`** (set as the XcodeBuildMCP
session default, bundle id `dev.conduit.mobile`). Confirm with `session_show_defaults`.

**Standard flow (MCP):**
```
build_sim → get_sim_app_path(platform:"iOS Simulator") → install_app_sim(appPath)
→ set_sim_appearance(mode:"dark"|"light") → launch_app_sim(env:{...}) → screenshot(returnFormat:"path")
→ Read the .jpg path to view it.
```
- `launch_app_sim`'s `env` map **auto-prefixes `SIMCTL_CHILD_`** — this sidesteps the documented
  "env didn't propagate" gotcha. Prefer it over raw `xcrun simctl`.
- **Wait ~1–2s after launch before screenshotting** or you get a blank/mid-animation frame (the harness
  screenshot usually lands fine, but if blank, relaunch + retry).

**Three launch modes:**
1. **Real app, jump to a tab:** `env: { "CONDUIT_TAB": "inbox|fleet|activity|settings" }`. This is the
   **most authoritative** check — it exercises real navigation and the `DebugSeeder` data (2 pending
   approvals + 5 hosts seeded on first run). Use this to verify the actual ported screens.
2. **Gallery harness (mock UI, no SSH):** `env: { "CONDUIT_GALLERY": "<route>" }`. Routes (see
   `DebugGalleryView.swift` switch): `review` (default), `components` (catalog — best for risk-chip/tone
   checks), `chat`, `diff`, `filepreview`, `onboarding`, `orb-connecting`, `orb-connected`, `blocks`
   (static mock transcript), `session` (the **real live SSH** block pipeline — see below).
   ⚠️ **The env KEY being present (even empty `""`) forces gallery mode.** To reach the real app, pass
   NO `CONDUIT_GALLERY` key at all.
3. **Live SSH block session** (`CONDUIT_GALLERY=session` + `CONDUIT_TEST_*`): see `CLAUDE.md` →
   "Running the live block session." Needs macOS Remote Login (sshd) on + the login password in Keychain
   (`security find-generic-password -s conduit-localhost-ssh -w`). Harnesses auto-trust the first host
   key (DEBUG only — **production paths must keep the TOFU prompt**).

**UI automation (when you need taps/scrolls, not just a screenshot):**
- `mcp__ios-simulator__ui_describe_all` → returns the a11y tree with **point-space** frames (NOT pixel).
  Use it to get exact tap coordinates; the screenshot is 368×800 px but the a11y frame is ~402×874 pt.
- `mcp__ios-simulator__ui_tap(x,y)` — coords are **points** (use the a11y frame centers, not screenshot
  pixels — they differ by the device scale).
- `mcp__ios-simulator__ui_swipe(x_start,y_start,x_end,y_end, duration:"0.4", delta:2)` — a fast
  `delta:9` flick often doesn't register as a scroll; use `duration:"0.4"` + small `delta` for a
  deliberate scroll. Schema is `x_start/y_start/x_end/y_end` (NOT x/y/x2/y2).
- **Gotcha:** the gallery `onboarding` route's later steps gate on a real SSH connection, so you can't
  click all the way through; verify reachable steps + trust the shared `ctaFooter` for the rest.

**Appearance:** always check both — `set_sim_appearance(mode:"dark")` and `"light"`.

---

## 8. macOS-beta / environment specifics & gotchas

- **OS:** Darwin 27.0.0 (macOS 26 "beta"). Platform string `darwin`, shell `zsh`.
- **zsh glob gotcha:** `grep -r --include=*.swift` **fails** in zsh (`no matches found`) because zsh
  globs the unquoted `*.swift`. Always quote: `--include='*.swift'`. (Bit me twice this session.)
- **`Glob` tool is unavailable** in this harness — use `Bash` `find`/`grep` instead.
- **Strict concurrency (Swift 6):** `InboxViewModel` vs `LiveInboxViewModel` are swapped in `AppRoot`;
  both must stay `@MainActor @Observable` with identical `approvals` visibility. New helper methods that
  touch `fleetStore` should be `@MainActor`.
- **Module visibility footgun:** types in `ConduitCore` (e.g. `AutonomyPreset`, `ApprovalBlastRadius`,
  `AgentVendorStatus`) need an **explicit `import ConduitCore`** even when transitively linked — SPM may
  not flag the omission but the app target will. When a symbol "can't be found in scope," check imports.
- **Sim already booted:** `boot_sim` returning "Unable to boot … Booted" is harmless.
- **`launch_app_sim` needs `bundleId` in session defaults** — it's set (`dev.conduit.mobile`); if you
  ever see "bundleId is required," call `session_set_defaults({bundleId:"dev.conduit.mobile"})`.
- **Device builds:** code signing + DeviceTesting entitlements apply; iCloud gated by
  `CONDUIT_ICLOUD_ENABLED`; sim-only bugs hide on device. Prefer XcodeBuildMCP device tools over raw
  `xcodebuild`.
- **Package manager for any JS/TS work:** `bun` only (never npm/yarn/pnpm) — user global rule.
- **No code comments** unless the WHY is non-obvious (user global rule); never docstrings that restate
  what code does.
- **Commit/push only when the user asks.** This session committed because the user said "continue and
  commit." Nothing was pushed; no PR opened. Commit messages end with the
  `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>` trailer.

---

## 9. Open SECURITY item (from automated commit review — address before merge)

**[MEDIUM] SSH-keys navigation not biometric-gated.** Added in `924c040f`
(`SettingsFeature/SettingsView.swift`, the `NavigationLink → KeysView` under SECURITY).

**Context / assessment:** `KeysView` performs destructive/sensitive ops on the Keychain
(generate / import / delete Ed25519 keys). The app already has an **app-launch Face ID lock**
(`appLockEnabled`), and this surface previously existed under the (now-dissolved) Library, so this is a
**relocation, not a new exposure** — but per-action gating is a legitimate defense-in-depth gap and the
reviewer is right not to wave it off. **Not yet fixed** (the user pivoted to requesting this handoff;
I chose to document rather than expand scope mid-pivot).

**Recommended fix (do in `KeysFeature`, consistent with `openSession`/`CredentialResolver`):**
- Gate `KeysViewModel.delete` behind a `.confirmationDialog` **+** `BiometricGate.shared.unlock(reason:
  "Authenticate to delete SSH key")`.
- Require `BiometricGate.shared.unlock(...)` before `importFromText`/`importFromFile` persists to Keychain.
- Consider deferring `vm.reload()` until after a one-shot unlock on screen entry, so private bytes aren't
  paged into memory by a casual settings tap.
- `KeysFeature` will likely need a `SecurityKit` dependency (where `BiometricGate` lives) — check
  `Package.swift` target deps; `SettingsFeature` already depends on `SecurityKit`, `KeysFeature` may not.

---

## 10. Subagent orchestration method (how this was parallelized — reuse it)

The user asked for parallel subagent work. The constraint: **all UI lives in one SPM package**, so
parallel agents running `swift build` simultaneously would deadlock the shared `.build`, and two agents
editing the same file would collide.

**The method that worked:**
1. **Foundations first, in a careful wave.** Shared files (`DSButton`, `InboxCards`, `Tokens`) and new
   components are edited before any screen depends on them. Dispatch 3 agents on **disjoint** file-sets:
   (a) Phase-0 cleanup, (b) shared-component updates, (c) new components.
2. **Then fan out screens in parallel, one agent per screen on disjoint files** (Fleet / Activity /
   Settings / Policy / Onboarding / Dispatch — none share a file).
3. **Agents are EDIT-ONLY.** They are explicitly told **not** to run `swift build`/`xcodebuild` (would
   deadlock). The **orchestrator** (you) owns: the consolidating `swift build`, the `build_sim`, and the
   light/dark screenshots, between waves.
4. **Every new init parameter MUST have a default value** so existing call sites keep compiling while
   agents work blind to each other.
5. Each agent **reports raw facts** (files touched, new public signatures, anything it couldn't source)
   — the orchestrator integrates and fixes the seams (e.g. the missing `import ConduitCore`, the
   unescaped-quote parse error in `DSDecisionSheet`'s preview that cascaded module-wide diagnostics).

**Recovery note:** mid-run the subagents once hit a "session limit · resets HH:MM" and returned with 0
tokens. They had written nothing to disk (tree stayed clean), so re-dispatching the identical wave after
the reset was safe. Always `git status` after an interrupted wave before re-dispatching.

---

## 11. Quick file/symbol map

- Tokens / rules: `DesignSystem/Tokens.swift`; `docs/audit/CONDUIT_UI_CONSISTENCY_RULES.md`.
- Buttons/chips/cards: `DesignSystem/Components/` (`DSButton`, `DSChip`, `InboxCards`, `ChatComponents`,
  `ProComponents`, `ManagementAtoms`, `Primitives`, `DSBlastRadiusBanner`, **`DSStatusHeader`**,
  **`DSSpendHero`**, **`DSDecisionSheet`**).
- Tabs/nav/root + Dispatch wiring + sheets: `AppFeature/AppRoot.swift` (`rootDestination`,
  `bridgeSessionActions`, `dispatchAgents`, `performDispatch`, `SettingsWithLibraryView`).
- Inbox + cards routing: `InboxFeature/InboxView.swift` (`pendingCard`), `ActivityView`,
  `BridgeAuditFeedView`.
- Settings: `SettingsFeature/SettingsView.swift` (sections + `TrustPrivacyView`), `PolicyEditorView`.
- Onboarding: `OnboardingFeature/OnboardingView.swift` (4-step `ctaFooter`).
- New screen: `AppFeature/DispatchView.swift`. SSH keys: `KeysFeature/KeysView.swift`.
- Live terminal pipeline (don't touch unless asked): `SessionFeature/` + `TerminalEngine/`; see
  `docs/block-terminal-implementation.md` and `CLAUDE.md` "Block terminal."
- Backend bridge: `daemon/` (Go `conduitd`); `SSHTransport/DaemonChannel.swift`
  (`dispatchAgent(agent:cwd:prompt:budgetUSD:)`).

---

## 12. Suggested next session opening move

1. `git status` (expect clean) + `git log --oneline -8` on `codex/uiux-audit`.
2. `cd Packages/ConduitKit && swift build` then `mcp__XcodeBuildMCP__session_show_defaults` +
   `build_sim` to confirm green baseline.
3. Tackle TODO #1 (SSH-keys biometric gate, §9) — smallest, security-relevant, self-contained.
4. Then TODO #2 (wire `DSDecisionSheet`) — the highest-visibility remaining design gap.
5. Screenshot each change light+dark via the `CONDUIT_TAB` real-app harness (§7) before committing.

Ask the user before pushing or opening a PR.
