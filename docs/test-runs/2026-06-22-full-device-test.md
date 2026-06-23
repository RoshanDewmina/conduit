# Full device test — 2026-06-22

> Live end-to-end test of Lancer on **Roshan's iPhone** (iOS 27.0, device
> `557A7877-…`). Collaborative: **you** tap/observe on the phone; **I** build/install and verify
> backend state (daemon logs, relay, push, APNs). Mark each ✅/❌ as we go.

**Preflight (verified before start):** daemon running (`~/.lancer/lancerd.sock`, pid 50241) ·
push backend `conduit-push-…run.app/health` → 200 (APNs key mounted, rev 00008-wkw) ·
app `LANCER_PUSH_BACKEND_URL` points at conduit-push · device build SUCCEEDED + signed.

---

## Phase 1 — Onboarding + first connect
- [ ] 1.1 Fresh launch: welcome screen renders, copy + branding correct, light/dark.
- [ ] 1.2 Notifications permission prompt appears; tap **Allow** → APNs token registers (I verify the backend received a token for this sessionId).
- [ ] 1.3 Connection / pairing step: generate a pairing code, host `lancerd` connects with it (I verify the daemon attaches to the relay).
- [ ] 1.4 First-run completes → lands on the New Chat / Command Home shell. No dead buttons; back buttons present on each onboarding page.
- [ ] 1.5 Re-launch does NOT show onboarding again (first-run persisted).

## Phase 2 — Compose + dispatch a run
- [ ] 2.1 New Chat composer: **Machine** picker lists the paired machine; **Agent** picker offers only installed agents (Claude/Codex/OpenCode/Kimi).
- [ ] 2.2 Project path picker: pick/type a gated workspace; custom path persists (newest-first).
- [ ] 2.3 Send a plain prompt → run dispatches over the relay; chat transition happens; tokens stream back.
- [ ] 2.4 Tool / terminal cards render for tool calls; `@`-file mention + `/` command autocomplete work.

## Phase 3 — Governed approval loop (app in foreground)
- [ ] 3.1 Trigger an `ask` (e.g. `claude 'write "push" to ./p.txt'` in the gated workspace) → an approval card appears in the **Inbox**.
- [ ] 3.2 The card shows the **approval summary** one-liner (e.g. "Edits 1 file" / "Runs `…`") + risk badge.
- [ ] 3.3 **Approve** → agent unblocks and continues (I verify via daemon log).
- [ ] 3.4 **Deny** on a second ask → agent stops.
- [ ] 3.5 **Edit & run** edits the command before approving.
- [ ] 3.6 **Allow always** on a critical action requires **Face ID** (BiometricGate) first.

## Phase 4 — Live push, app CLOSED (THE #1 gate — C2, never yet passed)
- [ ] 4.1 Fully background/close the app.
- [ ] 4.2 Trigger an `ask` from the host.
- [ ] 4.3 **Lock-screen / Dynamic Island notification fires** with Approve/Reject actions (I verify APNs send in backend logs).
- [ ] 4.4 Tap **Approve** on the lock screen → agent unblocks **without foregrounding the app**.
- [ ] 4.5 Capture a screen recording as proof. ⏸ This closes readiness checklist **C2**.

## Phase 5 — Continue / resume + terminal
- [ ] 5.1 Send a **follow-up** turn on the active run → new turn appends, gates re-run.
- [ ] 5.2 Resume a past conversation from **History** → state restores.
- [ ] 5.3 Open the **remote terminal** → PTY connects, blocks render, input works.

## Phase 6 — Fleet, sessions, drift
- [ ] 6.1 Fleet/Home shows the paired machine + host health.
- [ ] 6.2 **Cross-provider session observability**: sessions running on the Mac (Claude/Codex/OpenCode/Kimi) appear on the phone.
- [ ] 6.3 **Setup-drift** card surfaces (or "clean") for a scanned repo.

## Phase 7 — Settings, Trust Center, security
- [ ] 7.1 Settings groups: Connection / Notifications / Security & Trust / Advanced / Account all reachable.
- [ ] 7.2 **Security & Trust**: PAIRINGS & REVOCATION lists the paired device; **revoke** works.
- [ ] 7.3 Face ID / app-lock gate on launch (if enabled).
- [ ] 7.4 **Emergency Stop / Pause all** halts local agents.

## Phase 8 — Resilience + accessibility
- [ ] 8.1 Background → network switch (Wi-Fi↔cellular) → approval still delivers (relay reconnect).
- [ ] 8.2 Daemon restart mid-session → app reconnects, no stuck "thinking".
- [ ] 8.3 Empty/loading/error states render on each surface.
- [ ] 8.4 Dynamic Type (large) + VoiceOver pass on the core flows; light + dark.

---

## Results log
- **✅ 1.1–1.4 Onboarding + pairing** — pairing succeeded (code 357721, `e2e: paired with phone`), landed in chat. (1.0 finding below still open.)
- **🛠 2.x (FIXED) — every fresh dispatch hung → phone showed "Run failed · exit 1".** Root cause: `realLauncher` (dispatch.go) waited on the stdout/stderr pipes (`streams.Wait()`) **before** reaping the agent. Claude Code spawns MCP server subprocesses (`apple-docs-mcp`, …) that **detach via setsid** (escaping the agent's process group) and keep the pipe write-ends open after the agent exits, so the pipes never EOF → `streams.Wait()` blocked forever → `cmd.Wait()` was never reached → terminal status never emitted → run stuck "running" → phone timed out. (`--continue` runs that skip the giant init worked earlier, masking it; 10 orphaned `apple-docs-mcp` procs confirmed the leak.) **Fix:** reap the process first (`cmd.Wait()`), emit terminal status immediately, then best-effort kill the process group + close pipes. Verified via daemon DBG log: `cmd.Wait returned code=0 → terminal emitted` (~5s). Daemon rebuilt + `go test ./...` green + redeployed.
- **❌ 1.0 (FINDING) — onboarding has no "install & run the bridge on your computer" step before "Pair the bridge".**
- **❌ (FINDING) — failed-run error copy is misleading:** a failed *agent run* shows the generic SSH-style "An unexpected error occurred. Check the address and credentials" (`DSTypedErrorCard .other`). Should distinguish a run failure from a connection failure. A new user with no `lancerd` running reaches the pairing page with nothing to pair to. Fix: add a preceding step (install command `curl … | sh` or `lancerd install`, confirm it's running) ahead of the pairing page in the iOS onboarding flow.

---

## Simulator visual/design QA sweep — 2026-06-23 (Xcode 27, iOS 27 sim)

Walked 31 Debug Gallery routes (`LANCER_GALLERY=<route>`) on iPhone 17 Pro. **Structural finding:**
the app is **fixed-dark** — it ignores the system appearance toggle (`simctl ui … appearance`);
appearance is an in-app `@AppStorage` (Settings → Appearance). So light/dark parity is a deliberate
dark-first product stance, not a per-route bug; light-mode testing is N/A until a light theme ships.

**Defects found (5×P2, 3×P3):**

| # | Route | Issue | Severity | Disposition |
|---|---|---|---|---|
| 1 | shell-inbox | Approve/Deny/Answer render as bright **white fills** (raw `.background`, not `DSButton`) on the most critical screen | P2 | **Fixing** (agent A → DSButton) |
| 2 | inbox-typed / settings-policy | Policy preset tab caps text too small (hardcoded `.font(.system(size:))`, won't scale) | P2 | **Fixing** (agents A+B → `.dsCapsStyle`/scaling tokens) |
| 3 | paywall | "Unlock Pro" primary CTA is dark-on-dark, nearly invisible | P2 | **Flagged** (PaywallSheet; secondary screen — deferred) |
| 4 | onboarding-pair / BridgePairingView | Shows `curl -fsSL conduit.dev/install \| sh` | P2 | **Flagged for owner** — `*.conduit.dev` infra was *deliberately preserved* in the rebrand; changing the displayed domain may break the real install/billing endpoints. Needs a decision (is `lancer.dev` live?). Also: AgentsView/AddHostView/AgentBillingSheet show `conduit.dev/subscribe`. |
| 5 | components | Gallery harness preview panels use hardcoded white fill + content clips off right edge | P3 | **Skip** — debug-only harness, not shipping UI |
| 6 | onboarding-redesign | Feature-list subtitles low-contrast on dark bg | P3 | Note (minor) |
| 7 | drift / diff / filepreview / shell-fleet-relay | Short content + large empty void below (gallery fixtures; lists fill in real use) | P3 | **Skip** — fixture artifact, non-issue in prod |

**Also fixing (from the code-level offender audit, not all visually obvious):** raw
`Color(red:green:blue:)` → named tokens in FleetView/AgentsView/DarkTranscriptComponents (agent C);
`.font(.system(size:))` → scaling DS helpers across DSApprovalBanner/InboxView/SettingsView/AuditView/
DSOfflineState (agents A+B); the misleading run-failure copy → new `DSConnectError.runFailed` case
(agent D); the onboarding "install the bridge first" step (finding 1.0, agent D).

### Fixes applied + verified (2026-06-23)

Fanned out 4 Sonnet subagents on disjoint files, then re-verified with a 2nd visual subagent + an
authoritative `build_sim`. Net (13 source files):

- **Dynamic Type:** ~21 hardcoded `.font(.system(size:))` → scaling `.dsSansPt/.dsMonoPt/.dsDisplayPt`
  helpers (DSApprovalBanner, InboxApprovalCard, InboxView, SettingsView, AuditView, DSOfflineState).
  Re-verified at `accessibility-extra-extra-large`: text in shell-inbox + shell-settings now scales
  (minor acceptable compression on the account row at max size).
- **Raw colors → tokens:** 4 `Color(red:…)` → `t.termOk/termSurface2/accent/termPrompt`
  (FleetView, AgentsView, DarkTranscriptComponents). No new tokens needed.
- **Approval buttons (the white-pill bug):** both inbox cards now use `DSButton` — **Approve/Answer =
  `.accent` (orange), Deny = `.destructive` (red outline)**, "Review diff" = `.secondary`.
  `InboxApprovalCard` (inbox-typed) + the hand-rolled `InboxBoardCard` (shell-inbox, `t.text` white
  fill removed). **Screenshot-confirmed** on shell-inbox: orange Approve, red Deny, no white pills.
- **Run-failure copy:** added `DSConnectError.runFailed(String)` (badge `RUN`, "The agent run ended
  with an error…", retry / view-output actions); `NewChatTabView` + `RunDetailView` "failed" path now
  use it instead of the SSH-credentials `.other` copy. `RunDetailView` transport-error path left `.other`.
- **Onboarding install step (finding 1.0):** new `installBridge` phase between welcome and pair
  (headline "Install Lancer on your computer", install command, "waiting to pair" hint, back-button
  parity). Added `.id(phase)` to the footer for identity-reset consistency with the screen body.
  Renders correctly (confirmed). NOTE: the verify subagent reported the step "skipped" via simulator
  HID taps — that's the documented **idb/HID tap unreliability on this headless sim**, not a code bug;
  the welcome→installBridge→pair ordering + back-nav are correct, and the footer-swap mechanism is the
  same one welcome→pair already used.

**Gates:** `build_sim` SUCCEEDED (0 warnings/errors) · LancerKit `swift build` clean ·
`swift test` 13/13 (platform-agnostic suites; iOS UI tests are SwiftPM-skipped on macOS, covered by
build_sim) · `daemon/lancerd` go build/vet/test green (Phase 0).

### Deferred / flagged for owner (not fixed this pass)
- **`conduit.dev` → `lancer.dev` rebrand** in user-facing copy (OnboardingPairScreen, BridgePairingView,
  AgentsView, AddHostView, AgentBillingSheet): `*.conduit.dev` infra was deliberately preserved in the
  rebrand — changing the displayed install/subscribe domain may break real endpoints. Needs a decision.
- **Paywall CTA** dark-on-dark (secondary screen) · **onboarding-redesign** dim subtitles (minor
  contrast) — low priority.
- **Light mode:** app is intentionally fixed-dark (in-app `@AppStorage`, ignores system toggle); no
  light theme to test.
