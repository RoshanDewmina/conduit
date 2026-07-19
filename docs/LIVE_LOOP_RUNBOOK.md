# Lancer — Live Loop Runbook (governed approvals + notifications, end-to-end)

> **Purpose.** A self-contained, step-by-step procedure to bring up and prove Lancer's core loop:
> a real agent (Claude Code / Codex / OpenCode / Kimi) on a host → `lancerd` policy → the phone's
> Inbox → Approve/Reject → the agent unblocks → audit — **including push notifications while the app
> is backgrounded/closed**, and the **dispatch + `continue`** path.
>
> **How to use this doc.** Work top-to-bottom. Each **PHASE** ends with a `🛑 CHECKPOINT` — a concrete
> thing to see before continuing. If a checkpoint fails, stop and report the symptom; the **Triage**
> section maps symptoms to the exact file/function to inspect. The owner (Roshan) runs the human-gated
> steps (device, App Store, secrets); an agent can drive everything else and pause at checkpoints.
>
> **To hand this to an agent:** paste the prompt in the last section (“Agent execution prompt”). It
> references this file for the steps.

---

## 0. Context an executing agent needs (read once)

**The loop (daily heartbeat):**
```
agent PreToolUse hook ─▶ ~/.lancer/lancerd.sock ─▶ policyEngine.evaluate()
   │                                                      │
   │                              allow → audit+return    │ ask → blast-radius + queue
   │                              deny  → audit+return     ▼
   │                                          ┌─ SSH: lancerd serve relays to phone
   │                                          └─ Relay: POST push-backend /approval → APNs → phone
   ▼                                                      │
hook blocks ≤120s ◀── decision relayed back ◀── phone Approve/Reject (Inbox / lock-screen / Watch)
```

> ⚠️ **V1 TRANSPORT = E2E RELAY (corrected 2026-06-19).** V1 does **not** use SSH. The phone pairs to
> the `push-backend` relay; the resident `lancerd` connects to the same relay; phone ↔ relay ↔ daemon,
> end-to-end encrypted. **Phase 5b (relay) is the actual V1 loop — do it first.** The SSH phases below
> (Phase 3, `DaemonChannel`/`lancerd serve`) are a **legacy/secondary harness** kept because the SSH
> path is already proven and convenient for local sim testing; they are *not* the V1 story. (This runbook
> still leads with SSH for historical reasons — reorder pending.)

**Two transports — both re-run policy + budget gates:**
- **E2E relay (V1):** the phone (`E2ERelayClient` + `E2ERelayBridge`) pairs to `push-backend`'s relay; the resident daemon connects host-side; decisions route through `ApprovalRelay.forwardDecisionOnly`. **No phone-held SSH session.** This is the path V1 ships.
- **SSH (legacy/secondary):** the app opens an SSH session and launches `lancerd serve`, which *attaches* to the resident `lancerd daemon`. Code: `DaemonChannel` (`SSHTransport/`), armed in `AppRoot.startSession` / `SessionViewModel.onReconnected`. Useful as a local proven harness; not the V1 transport.

**Notifications:** `push-backend` holds the APNs `.p8` and POSTs to APNs when an `ask` escalates. The device registers its APNs token via `Lancer/LancerApp.swift` → `Notifications.registerDeviceToken(sessionID:backendURL:)`. **The `sessionId` used at registration MUST equal the one in the relay decision POST** (`DeviceIdentity.sessionID()`) or the backend can't map token↔session (this was MAJOR-8).

**What's already PROVEN (don't re-litigate):** the full SSH loop on the simulator + localhost sshd — real `claude` → daemon → policy → Inbox card → Approve → agent unblocked (audit `approve` ~+13–20s, well under the 120s fail-closed timeout). Two bugs were found & fixed there: (1) TOFU first-connect didn't arm the daemon channel — fixed in `SessionViewModel.trustHostKey()` (now calls `onReconnected?()`); (2) UUID case mismatch dropped every decision — fixed by case-insensitive normalization in lancerd `approvalStore`. Evidence: `docs/test-runs/2026-07-06-tier-0-live-cursor-shell-proof.md` and `ARCHITECTURE.md` §0.1.

**What is NOT yet proven (the point of this runbook):**
- **APNs on a physical device while the app is closed — on the *current tip*** — simulators can't receive real APNs. **Historical PASS** 2026-07-08 evening on tip `732071a7` ([`docs/test-runs/2026-07-08-tier0-5c-retest-results.md`](test-runs/2026-07-08-tier0-5c-retest-results.md)); tip has moved, so re-proof on what we install today → [`docs/test-runs/2026-07-09-tier0-device-proof-results.md`](test-runs/2026-07-09-tier0-device-proof-results.md).
- **Real *remote* host** (only localhost-sim subset done).
- **`continue`/follow-up** live for each vendor (argv exists; verify per vendor — see `vendor-cli-adapter-audit`).

**Fail-closed:** if the resident daemon is down, mutating hook kinds (`command`/`patch`/`fileWrite`/…) **hold (exit 1)**; only read-only kinds may fail-open and only with `LANCER_HOOK_READONLY_FAIL_OPEN=1`.

**Key paths:** binary `~/.lancer/bin/lancerd` · socket `~/.lancer/lancerd.sock` · queue `~/.lancer/queue.json` · policy `~/.lancer/policy.yaml` (+ repo-local `<cwd>/.lancer/policy.yaml`) · audit `~/.lancer/audit.log` (0600 JSONL). Hooks: `docs/lancer-hook.sh` (Claude), `docs/codex-lancer-hook.sh`, `docs/opencode-lancer-hook.sh`.

---

## PHASE 1 — Build everything from current source

> The shipped prebuilt `lancerd-darwin-arm64` is **stale** (Swift 0.1.0, no policy engine). Always rebuild lancerd from Go.

```bash
cd /Users/roshansilva/Documents/command-center

# 1a. lancerd (Go) — the ONLY canonical daemon
cd daemon/lancerd && go build -o lancerd . && go test ./... && cd ../..

# 1b. LancerKit engines (fast inner loop; does NOT compile #if os(iOS) UI)
cd Packages/LancerKit && swift build && cd ../..
```
Then the **authoritative iOS app-target build** (catches strict-concurrency breaks SPM misses). Prefer XcodeBuildMCP:
`session_set_defaults` → project `Lancer.xcodeproj`, scheme `Lancer`, sim `iPhone 17 Pro` → `build_sim`.
CLI fallback:
```bash
xcodebuild -project Lancer.xcodeproj -scheme Lancer \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/lancer-dd build
```

🛑 **CHECKPOINT 1:** `go test` green, app-target build SUCCEEDED (0 errors). If the app build fails but `swift build` passed, it's almost certainly a strict-concurrency error in a `#if os(iOS)` file — read the `file:line` and fix before continuing.

---

## PHASE 2 — Stand up the resident daemon + a hook (host side)

Use **localhost** first (fastest, repeatable). Prereqs: macOS **Remote Login ON** (System Settings → General → Sharing → Remote Login), and the login password stored in Keychain:
```bash
security add-generic-password -s 'lancer-localhost-ssh' -a "$USER" -w 'YOUR_LOGIN_PW' -U
```

Install + start the resident daemon:
```bash
cd daemon/lancerd
./lancerd install
launchctl unload ~/Library/LaunchAgents/dev.lancer.lancerd.plist 2>/dev/null || true
launchctl load   ~/Library/LaunchAgents/dev.lancer.lancerd.plist
test -S ~/.lancer/lancerd.sock && ~/.lancer/bin/lancerd version
```

Write a policy that forces an **ask** (so a card actually appears) and proves allow/deny:
```bash
cat > ~/.lancer/policy.yaml <<'YAML'
rules:
  - id: allow-echo
    effect: allow
    match: "echo*"
  - id: deny-rmrf
    effect: deny
    match: "rm -rf*"
  # everything else (e.g. fileWrite) falls through to default: ask
YAML
```

Wire the **Claude Code** hook **project-scoped to a throwaway workspace** (so you never gate your own working Claude session):
```bash
mkdir -p /tmp/lancer-e2e-workspace/.claude
cp docs/lancer-hook.sh ~/.claude/hooks/lancer-hook.sh && chmod 700 ~/.claude/hooks/lancer-hook.sh
cat > /tmp/lancer-e2e-workspace/.claude/settings.json <<'JSON'
{ "hooks": { "PreToolUse": [ { "hooks": [ { "type": "command", "command": "~/.claude/hooks/lancer-hook.sh" } ] } ] } }
JSON
```
(For Codex/OpenCode/Kimi hook install paths see `docs/resident-daemon-owner-steps.md`.)

Synthetic sanity (no phone) — confirms policy engine without the app:
```bash
cd daemon/lancerd && LANCERD_BINARY=./lancerd ../../scripts/validation/resident-bridge-smoke.sh
```

🛑 **CHECKPOINT 2:** socket exists, `lancerd version` prints a Go build (not 0.1.0), smoke script PASSes. With the daemon **stopped**, a `fileWrite` hook should print *“holding mutating action”* and exit 1 (fail-closed).

---

## PHASE 3 — Workspaces approval loop on the simulator

This is the proven path; use it to confirm your environment before going to device. The repeatable harness:
```bash
./scripts/relay-regression.sh
```
What it does: builds the app, installs to the booted sim, launches with `LANCER_DAEMON_E2E=1` +
`LANCER_DESTINATION=review` (Workspaces review surface — see `scripts/relay-regression.sh:70–78`),
seeds a localhost host, screenshots `before-approval`, waits for you to tap **Approve** on the
Review surface, screenshots `after-approval`. Do **not** use retired `LANCER_CURSOR_SHELL*` flags.

Manual equivalent (if you want to drive it yourself):
```bash
xcrun simctl boot "iPhone 17 Pro" 2>/dev/null || true
PW="$(security find-generic-password -s lancer-localhost-ssh -w)"
xcrun simctl install booted /tmp/lancer-dd/Build/Products/Debug-iphonesimulator/Lancer.app
xcrun simctl terminate booted dev.lancer.mobile 2>/dev/null; sleep 2
env SIMCTL_CHILD_LANCER_DAEMON_E2E=1 SIMCTL_CHILD_LANCER_DESTINATION=review \
    SIMCTL_CHILD_LANCER_TEST_HOST=127.0.0.1 SIMCTL_CHILD_LANCER_TEST_USER="$USER" \
    SIMCTL_CHILD_LANCER_TEST_PW="$PW" SIMCTL_CHILD_LANCER_TEST_PORT=22 \
    xcrun simctl launch booted dev.lancer.mobile
sleep 12; xcrun simctl io booted screenshot /tmp/loop-card.png && open /tmp/loop-card.png
```
Then from the throwaway workspace, drive a real escalation:
```bash
cd /tmp/lancer-e2e-workspace && claude 'write the text "live-loop" to ./tc.txt'
```

🛑 **CHECKPOINT 3 (the core loop):**
- A pending **Inbox card** appears with real cwd / file / matched-rule / blast-radius.
- Tap **Approve** → within seconds `~/.lancer/audit.log` gets an `approve` entry (`tail -1 ~/.lancer/audit.log`) and `./tc.txt` is created.
- Tap **Reject** on a fresh run → file is NOT created; audit shows the rejection.
- Verify the agent actually unblocked (claude continues), not a 120s timeout→deny.

> If the session header reads **Offline** and no card arrives: the daemon channel didn't stay attached. See Triage A.

---

## PHASE 4 — Dispatch + `continue` (New Chat → run → follow-up)

From the **New Chat** surface (the app home), dispatch a run and then continue it:
1. New Chat → pick an agent (SSH slot or Relay) → enter a prompt → send. A run starts (`performDispatch` → `dispatchAgent`, status `started` with a `runId`).
2. When it finishes a turn, use the **follow-up** composer to send another prompt. This calls `continueRun` → `continueArgv` (Claude `--continue -p`, Codex `exec resume --last`, Kimi `--continue`, OpenCode equivalent), **with a new Lancer `runId`** but the vendor's session continuity underneath. Gates re-run.

🛑 **CHECKPOINT 4:** the first dispatch streams tokens into the transcript and forms tool-call cards (`InlineChatToolCard`); the follow-up continues the *same* vendor conversation (it remembers prior context) and re-passes policy. Confirm per vendor you care about — **don't assume**; CLI resume flags drift (`vendor-cli-adapter-audit`). Note any vendor whose `continue` misbehaves.

---

## PHASE 5 — Notifications: relay + APNs (the unproven product promise)

### 5a. Backend secrets (owner-gated, one-time)
The relay/APNs lives in the deployed `push-backend`. **The shipping app + daemon talk to `https://conduit-push.fly.dev` (Fly.io, always-on `iad`)** — this is the backend the device registers its APNs token against, so it must hold the APNs secrets. (`RelaySettings.defaultURLString`, `relay_install_helper.go:defaultRelayURL`, and `project.yml` all point here.) `/health` does **not** prove APNs delivery; push reads its configuration on send. Confirm these secret names are deployed on Fly without printing their values:
`APPROVAL_RELAY_SECRET`, `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_BUNDLE_ID`, `APNS_KEY_PATH=/tmp/secrets/apns.p8`, and `APNS_KEY_P8_BASE64`. The entrypoint decodes the key into the container's temporary filesystem; never commit the `.p8`.

### 5b. Relay pairing (works on sim — proves the decision-relay path, not APNs delivery)
Pair the phone to the relay in **Settings → Connection** (the app generates a pairing code; the host side connects with it). In DEBUG you can headless-pair the sim with `SIMCTL_CHILD_LANCER_RELAY_CODE=<6-digit code>`. With relay paired and **no SSH session**, an escalated approval should still reach the Inbox (delivered via `lancerE2EApprovalReceived` → mapped into the active `InboxViewModel`).

🛑 **CHECKPOINT 5b:** with SSH disconnected but relay paired, trigger an `ask` → the card still appears in the Inbox, and Approve still unblocks the agent (decision rides the relay).

### 5c. APNs while app is closed — **physical device only**
Simulators cannot receive production APNs. On a real iPhone (signed dev build, Push entitlement, `aps-environment`):
1. Launch Lancer once, accept notifications → device registers its APNs token (`LancerApp.didRegisterForRemoteNotificationsWithDeviceToken` → `Notifications.registerDeviceToken`). Confirm the backend received the token for this `sessionId`.
2. **Background or fully close** the app.
3. From the host, trigger an `ask` (e.g. `claude 'write the text "push" to ./p.txt'` in the gated workspace).
4. A **lock-screen / Dynamic Island** notification should fire with the approval context, with **Approve / Reject** actions.
5. Tap **Approve** on the lock screen → the decision routes through `LancerNotificationDelegate` → `.lancerApprovalAction` (and, on cold launch, `ApprovalActionBuffer` drain) → agent unblocks **without opening the app to the foreground first**.

🛑 **CHECKPOINT 5c (THE milestone):** backgrounded/closed app receives the push, lock-screen Approve unblocks the host agent, and `audit.log` shows the decision with `source` reflecting the notification path. Capture a screen recording. **Historical PASS** 2026-07-08 evening ([`docs/test-runs/2026-07-08-tier0-5c-retest-results.md`](test-runs/2026-07-08-tier0-5c-retest-results.md), Approve `79137ae4…` / Reject `461bc3e0…`). **Current tip re-proof PENDING** — record today's run in [`docs/test-runs/2026-07-09-tier0-device-proof-results.md`](test-runs/2026-07-09-tier0-device-proof-results.md); treat any failure here as P0 and report the exact step.

---

## PHASE 6 — TestFlight distribution (share with others)

Do Phase 5c first — **never** hand testers a build whose core loop you haven't proven on your own
device. Phase 6 is owner-gated (Apple ID + App Store Connect GUI); the steps below are the exact
sequence. Facts pulled from `project.yml`: app bundle `dev.lancer.mobile`, team `39HM2X8GS6`,
`CODE_SIGN_STYLE: Automatic`, `aps-environment: production`, version `1.0.0 (1)`.

### 6a. App Store Connect record (= checklist D2, one-time)
1. App Store Connect → **Apps → +** → New App. Platform iOS, bundle ID **`dev.lancer.mobile`**
   (register it under Certificates, IDs & Profiles first if it's not in the dropdown), SKU `lancer`.
2. Register App IDs + matching capabilities for **every embedded target** that ships in the archive
   so automatic signing can mint profiles: `dev.lancer.mobile` (Push, App Groups, CloudKit if
   `ENABLE_CLOUDKIT` is on), `dev.lancer.mobile.widget`, `dev.lancer.mobile.liveactivity`. (Watch
   targets are **not** embedded today — `project.yml` leaves the embed commented out — so skip them
   until re-embedded.)
3. IAP: create Non-Consumable **`dev.lancer.mobile.pro`** as **Founder's Edition** at
   **$79–99** (owner picks ASC tier in band; see [`SHIP_PLAN.md`](../SHIP_PLAN.md) decision 6).
   (TestFlight can run without it,
   but sandbox-testing the purchase needs it to exist — checklist C5.)
4. Encryption: set **`ITSAppUsesNonExemptEncryption`** (the app uses only standard TLS/ChaCha20 →
   exempt) so each upload skips the manual compliance prompt.

### 6b. Pre-archive checks
- `aps-environment` is **production** → the build talks to the **production** APNs + the deployed
  `push-backend`. That matches the running backend (`APNS_BUNDLE_ID=dev.lancer.mobile`, D1 ✅). Good.
- Confirm `LANCER_PUSH_BACKEND_URL` is set in the **Release** build settings to
  `https://conduit-push.fly.dev`. A blank URL ships a build that
  can't reach push.
- Entitlements/CloudKit consistency: if you archive with `Lancer.entitlements` (iCloud on), set
  `ENABLE_CLOUDKIT=true`; if with `Lancer-DeviceTesting.entitlements`, keep it **false**
  (`project.yml:91`). Mismatch = validation failure at upload.
- Bump the build number every upload (App Store Connect rejects a duplicate `CURRENT_PROJECT_VERSION`
  for the same `MARKETING_VERSION`): `agvtool next-version -all` or bump `CURRENT_PROJECT_VERSION` in
  `project.yml`, then `xcodegen generate`.

### 6c. Archive + upload
```bash
cd /Users/roshansilva/Documents/command-center
xcodegen generate                      # regenerate Lancer.xcodeproj from project.yml
xcodebuild -project Lancer.xcodeproj -scheme Lancer \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/Lancer.xcarchive \
  archive
```
Then either:
- **Xcode Organizer** (simplest, recommended): Window → Organizer → select the archive →
  **Distribute App → TestFlight (Internal Only / App Store Connect)** → automatic signing → Upload.
- **CLI:** `xcodebuild -exportArchive -archivePath build/Lancer.xcarchive -exportPath build/export
  -exportOptionsPlist ExportOptions.plist` (method `app-store`), then upload `build/export/Lancer.ipa`
  with **Transporter.app** or `xcrun altool --upload-app`.

Processing on App Store Connect takes ~5–30 min before the build appears in TestFlight.

### 6d. TestFlight testers
- **Internal** (up to 100, your team members on the account): TestFlight tab → Internal Testing →
  add testers → they get it **immediately**, no review.
- **External** (up to 10k, anyone by email/public link): create a group, attach the build → submit
  for **Beta App Review** (usually <24h for the first build). Add **Test Information** (what to test,
  a demo pairing flow, contact email) or review bounces it.
- Tester instructions to send: install **TestFlight** from the App Store → open your invite link →
  Install Lancer → on first launch **accept notifications** (required for the approval loop) → pair
  with their own machine's `lancerd` (`curl … | sh` installer + pairing code). Without a paired
  machine the app has nothing to steer.

🛑 **CHECKPOINT 6:** an external tester on a different Apple ID installs from TestFlight, pairs their
own machine, and completes one approve-from-lock-screen loop (Phase 5c) end-to-end. That's the
"others can use it" bar. Update checklist **D5** only after a real tester confirms it.

---

## PHASE 7 — Cross-device conversation sync (two-device QA)

> Proves the feature in ARCHITECTURE.md §11.2: host-owned ledger is execution truth, CloudKit is the
> Apple-device read-continuity mirror, conflicts are explicit (never silently merged), and offline
> sends never silently queue. **This phase requires two Apple devices signed into the same iCloud
> account** (two physical devices, or one physical device + one simulator for the checks that don't
> depend on real CloudKit push/subscription delivery — `CloudSync`/`ConversationSyncEngine` are
> simulator no-ops, so simulator-only devices can't prove CloudKit propagation, only host-ledger
> behavior). Device Hub (Xcode 27) or `devicectl`/`simctl` can drive both simultaneously.

Prereqs: Phase 1 build, Phase 2 daemon up, both devices paired to the same host (relay or SSH).

1. **Start on A, appears on B.** New Chat on device A, send a prompt, let it complete. On device B, open
   the Workspaces thread list (pull to refresh, background/foreground to trigger
   `ConversationSyncEngine.syncNow()`, or wait for the best-effort `CKDatabaseSubscription` silent-push
   path) and confirm the conversation and its turns appear. Silent-push delivery is not yet hardware-proven,
   so capture whether the update arrived automatically or required a manual refresh.
2. **Follow-up from B while host is online.** From B, open that same thread and send a follow-up. Confirm
   it dispatches through the host (not a local-only echo) and streams a real reply.
3. **Kill + reinstall A.** Force-quit and delete the app on A, reinstall, sign back into the same
   Lancer/iCloud account. Confirm the conversation from step 1 reappears via the CloudKit mirror even
   before A re-pairs to the host.
4. **Conflict.** Open the same thread on both A and B, and send from both within the same few seconds.
   Confirm exactly one send succeeds and the other surfaces the `.conflict` `ConversationSyncBanner`
   ("Conversation changed on another device") with Refresh + Resend — not a silent merge or a duplicate turn.
5. **Host offline.** Disconnect the host (stop `lancerd` or disconnect its network) mid-thread on A.
   Confirm the transcript stays readable (from the local mirror / CloudKit) and the composer shows the
   `hostOffline` state — Send is blocked, not silently queued or auto-sent on reconnect.
6. **Observed-session import.** On the host, start a session directly in a terminal (not through Lancer),
   then from a device's Home → "Sessions on this Mac" open it as an `ObservedSessionView` and use the
   overflow menu's **Import to Lancer**. Confirm it navigates into a new durable thread, and that a
   follow-up sent from that thread resumes the *exact* vendor session (not latest-in-cwd).

🛑 **CHECKPOINT 7:** all six steps above behave as described. Record which steps ran on two physical
devices vs. one physical + one simulator (device combos, since simulator legs can't prove real CloudKit
propagation). Update `docs/PUBLISH_READINESS_CHECKLIST.md`'s CloudKit conversation-mirror entries only
for the steps you actually verified on physical hardware — do not mark cross-device CloudKit propagation
green from a simulator-only run, same rule as APNs (Phase 5c).

---

## Triage (symptom → where to look)

| Symptom | Likely cause | Inspect |
|---|---|---|
| **A.** Session header “Offline”, no card over SSH | daemon channel not attached (the pass-1 bug class) | `AppRoot.startSession` channel arm; `SessionViewModel.trustHostKey()` must call `onReconnected?()`; confirm a `lancerd serve` process persists (`pgrep -fl "lancerd serve"`). Heavy interactive zsh can wedge the unified shell. |
| **B.** Card appears, Approve does nothing, agent times out (120s→deny) | decision not delivered / ID mismatch | lancerd `approvalStore` case-insensitive lookup (fixed); over relay, `ApprovalRelay.forwardDecisionOnly`; check `sessionId` parity (reg vs decision POST). |
| **C.** Hook auto-allows everything | hook not gating / daemon governance missing | confirm policy `default: ask`; confirm lancerd is the **Go** build (not 0.1.0); confirm hook is the project-scoped one. |
| **D.** Everything holds (exit 1) | fail-closed: daemon unreachable | socket present? launchd loaded? |
| **E.** No push on device | APNs env not set / token not registered / sessionId mismatch | `push-backend` secrets (5a); `registerDeviceToken` actually called; backend token map keyed by the same `sessionId`. |
| **F.** `continue` errors for a vendor | argv/flag drift | `continueArgv` in `dispatch.go`; re-run `which`/`--version`/`--help`; `vendor-cli-adapter-audit`. |
| **G.** A conversation started on device A never appears on device B | silent-push delivery for the `CKDatabaseSubscription` is not hardware-proven yet; B may still need foreground/`syncNow()`; or B isn't signed into the same iCloud account | force a foreground/pull-to-refresh on B; confirm both devices' iCloud account; `ConversationSyncEngine.syncNow()` / `SyncStatusView`'s "Sync now"; collect device console logs for CloudKit notification routing. |
| **H.** Concurrent sends from two devices both appear to succeed instead of one conflicting | `baseSeq` compare didn't run, or the coordinator swallowed the conflict response | `conversationsAppend` in `conversation_rpc.go` (status must be `"conflict"` on stale `baseSeq`); `ConversationSyncCoordinator`'s `case "conflict"` handling. |

---

## Done / report format

After a run, report: which phases passed (with checkpoint evidence — audit tail line, screenshot path), which failed (symptom + Triage row), exact commands/MCP tools used, and any vendor whose dispatch/continue misbehaved. Update `docs/PUBLISH_READINESS_CHECKLIST.md` (C1/C2/D1–D3) **only** for checks you actually ran. Do not mark device APNs (C2) green from a simulator.

---

## Agent execution prompt (paste this)

```
You are executing Lancer's live-loop bring-up. Repo: /Users/roshansilva/Documents/command-center.

FIRST: invoke the `lancer-context-onboarding` skill, then read docs/LIVE_LOOP_RUNBOOK.md in full and
ARCHITECTURE.md §0.1 + §4.1. The app home is **Workspaces** (`AppRoot.readyRoot` →
`NavigationStack { WorkspacesView() }`), not a tab bar; DEBUG deep-links use `LANCER_DESTINATION`.
`lancerd` is the Go source under daemon/lancerd (the shipped prebuilt binary is stale — rebuild it).

GOAL: bring up and prove the governed-approval loop end-to-end per the runbook's phases, pausing at each
🛑 CHECKPOINT so the owner can inspect. Drive Phases 1–4 yourself (build, daemon, SSH loop on the
simulator, dispatch+continue). For Phase 5c (APNs on a physical device, app closed) you can prepare and
verify backend/registration, but the device tap is owner-run — stop and hand off with exact steps.

RULES:
- Verify with the authoritative builds: `go test ./...` from daemon/lancerd, and the XcodeBuildMCP
  app-target build (NOT just `swift build`). Use the `lancer-verification-gate` skill to choose checks.
- Never gate the owner's own Claude session — keep the test hook project-scoped to /tmp/lancer-e2e-workspace.
- Build explicit argv; never sh -c an interpolated prompt. Before touching dispatch.go run `vendor-cli-adapter-audit`.
- Treat existing uncommitted changes as the owner's in-flight work; do not revert them. Do not commit unless asked.
- At each checkpoint, STOP and report: what you saw (audit tail line / screenshot path), pass/fail, and the
  exact next action. If a checkpoint fails, use the Triage table — name the file/function you'd inspect — and wait.
- Do NOT mark physical-device APNs (checklist C2) green from a simulator. Report honestly.

Start with Phase 1 and report at CHECKPOINT 1.
```
