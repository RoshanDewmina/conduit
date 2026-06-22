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

**What's already PROVEN (don't re-litigate):** the full SSH loop on the simulator + localhost sshd — real `claude` → daemon → policy → Inbox card → Approve → agent unblocked (audit `approve` ~+13–20s, well under the 120s fail-closed timeout). Two bugs were found & fixed there: (1) TOFU first-connect didn't arm the daemon channel — fixed in `SessionViewModel.trustHostKey()` (now calls `onReconnected?()`); (2) UUID case mismatch dropped every decision — fixed by case-insensitive normalization in lancerd `approvalStore`. Evidence: `docs/test-runs/2026-06-12-live-loop-pass1.md`.

**What is NOT yet proven (the point of this runbook):**
- **APNs on a physical device while the app is closed** — simulators can't receive real APNs. This is the #1 unverified product promise.
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

## PHASE 3 — SSH loop on the simulator (Approve unblocks the agent)

This is the proven path; use it to confirm your environment before going to device. The repeatable harness:
```bash
./scripts/relay-regression.sh
```
What it does: builds the app, installs to the booted sim, launches the **session harness** (`LANCER_GALLERY=session`) with `LANCER_TEST_AUTOCMD=claude` so a block forms without typing, screenshots `before-approval`, waits for you to tap **Approve**, screenshots `after-approval`.

Manual equivalent (if you want to drive it yourself):
```bash
xcrun simctl boot "iPhone 17 Pro" 2>/dev/null || true
PW="$(security find-generic-password -s lancer-localhost-ssh -w)"
xcrun simctl install booted /tmp/lancer-dd/Build/Products/Debug-iphonesimulator/Lancer.app
xcrun simctl terminate booted dev.lancer.mobile 2>/dev/null; sleep 2
env SIMCTL_CHILD_LANCER_GALLERY=session \
    SIMCTL_CHILD_LANCER_TEST_HOST=127.0.0.1 SIMCTL_CHILD_LANCER_TEST_USER="$USER" \
    SIMCTL_CHILD_LANCER_TEST_PW="$PW" SIMCTL_CHILD_LANCER_TEST_AUTOCMD='claude' \
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
The relay/APNs lives in the deployed `push-backend` (`https://35.201.3.231.sslip.io/health` → 200). `/health` does **not** prove APNs is configured (push reads env lazily at first send). Confirm these are set on the *running* instance (`docs/push-backend-deploy-env.md`):
`APPROVAL_RELAY_SECRET`, `APNS_KEY_ID=L8LVU9X82W`, `APNS_TEAM_ID=39HM2X8GS6`, `APNS_BUNDLE_ID=dev.lancer.mobile`, `APNS_KEY_PATH=/secrets/apns.p8`. `.p8` source: `~/Downloads/Personal-Docs/AuthKey_L8LVU9X82W.p8` (never commit).

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

🛑 **CHECKPOINT 5c (THE milestone):** backgrounded/closed app receives the push, lock-screen Approve unblocks the host agent, and `audit.log` shows the decision with `source` reflecting the notification path. Capture a screen recording. **This is the gate that's never been passed — treat any failure here as P0 and report the exact step.**

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

---

## Done / report format

After a run, report: which phases passed (with checkpoint evidence — audit tail line, screenshot path), which failed (symptom + Triage row), exact commands/MCP tools used, and any vendor whose dispatch/continue misbehaved. Update `docs/PUBLISH_READINESS_CHECKLIST.md` (C1/C2/D1–D3) **only** for checks you actually ran. Do not mark device APNs (C2) green from a simulator.

---

## Agent execution prompt (paste this)

```
You are executing Lancer's live-loop bring-up. Repo: /Users/roshansilva/Documents/command-center.

FIRST: invoke the `lancer-context-onboarding` skill, then read docs/LIVE_LOOP_RUNBOOK.md in full and
ARCHITECTURE.md §0.1 + §4.1. The app home is a sidebar/New Chat shell, not a tab bar. lancerd is the
Go source under daemon/lancerd (the shipped prebuilt binary is stale — rebuild it).

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
