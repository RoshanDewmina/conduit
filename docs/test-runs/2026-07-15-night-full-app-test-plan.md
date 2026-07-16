# Lancer — full-app test plan & 2026-07-15 night session report

> **What this is.** A self-contained report of everything built in the 2026-07-15 night
> session **and** a step-by-step manual test script for the *entire* app, written so a fresh
> agent (no prior context) or the owner can execute it top to bottom. Every step lists the
> exact action, the expected result, and what to do if it fails.
>
> **Build under test:** branch `integration/2026-07-15-night` (rollup of PRs #120–#135;
> plus #136 push-backend tests, #137 security triage). Device build was installed on
> "Roshan's iPhone" (iOS 27) at ~22:04 and the phone paired at 22:07:44 (daemon log).
>
> **Canonical sources this complements:** `docs/LIVE_LOOP_RUNBOOK.md` (the governed-approval
> loop in depth), `docs/PUBLISH_READINESS_CHECKLIST.md` (launch gates), `docs/CHANGELOG.md`
> (append-only agent change log). If a step here disagrees with the runbook, the runbook wins
> for the core loop; this doc wins for the tonight-shipped features.

---

## Part A — What we built tonight (PR-by-PR)

| PR | Area | What changed | How you'll see it (test section) |
|----|------|--------------|----------------------------------|
| #120 | Composer | The home "Plan, ask, build…" pill now **morphs in place** into the composer card instead of presenting a detached drawer/sheet | §5.1 |
| #121 | Thread list | Per-row **diff stats** (+adds/−dels), Connected/Disconnected **liveness**, relative time, **unread dot**, last-message preview | §5.2 |
| #122 | Review | "Review +X −Y" pill copy, "PR not opened yet" hint card, PR actions menu (Open/Close PR), diff card capped at 3 files + "N more" | §5.3 |
| #123 | Transcript | Post-turn **activity summary** rows ("Worked Ns · Edited N files · +X −Y"), inline **to-dos checklist** card, **markdown tables** | §5.4 |
| #124 | Live thread | "N running tasks" **pill** → **Background tasks sheet**; live-thread nav shows session title + repo subtitle instead of "Chat" | §5.5 |
| #125 | Siri | Donation cadence refreshes on 7 real state changes; `NSSiriUsageDescription` added; AppIntents live-execution test (device-only) | §5.6 |
| #127 | Decrypt fix | Desktop Claude Code sessions with extended-thinking blocks no longer show "Decryption failed" | §5.7 |
| #129 | Polish | Removed non-functional mic icons from composers; Profile "Help" row now opens GitHub Issues | §5.8 |
| #130 | Onboarding | First-run welcome screen: what Lancer is, caution-tier picker, "Pair your Mac" CTA, skippable | §2 (you'll hit it on a fresh install) |
| #131 | Live thread | **Mid-run feedback**: type while a run is active → it queues and sends when the turn finishes; **permission-mode pill** (autonomy preset) | §5.9 |
| #133 | Reliability | Honest **empty / loading / error** states on Workspaces, Thread list, Search, Thread detail, file tree, composer upload | §5.10 |
| #134 | Thread list | **Status filter**, **Source filter**, **Customize sheet** (group by, metadata toggles) | §5.11 |
| #135 | Governance | **Emergency Stop** (P0), **policy editor**, **audit feed** wired into Settings | §4 (Emergency Stop) + §5.12 |
| #126 | Skills/docs | Risk-tiered `agent-oracle-harness` skill, corrected publish audit, mandatory `docs/CHANGELOG.md` rule | (process, not user-facing) |
| #128 | Docs | Stale-doc purge: 32 deletions, 17 corrections; B4 verified, B7 audit recorded | (docs) |
| #136 | Backend | Ported stashed push-backend regression tests (APNs redaction, contentHash) | `go test` only |
| #137 | Security | C6 semgrep triage: 14 findings, 0 actionable | (docs) |

**Not done tonight (owner-gated / next session):** merging these 18 PRs; App Store Connect
setup (IAP, screenshots, privacy label, CloudKit schema promotion); the vanity-domain cutover.
Two-device CloudKit sync QA needs a second Apple device.

---

## Part B — Environment setup (what a fresh agent must confirm first)

The build is already installed and paired. A fresh agent picking this up should confirm the
ground truth before testing, because it changes across sessions:

```bash
# 1. Resident daemon running?
launchctl list | grep dev.lancer.lancerd        # expect a PID, exit 0
tail -3 ~/.lancer/lancerd.stderr.log            # expect "connected to relay as daemon"

# 2. Phone paired? (look for a "paired with phone" AFTER the most recent pair-code generation)
grep "paired with phone" ~/.lancer/lancerd.stderr.log | tail -1

# 3. Device connected + which build?
xcrun devicectl list devices | grep -i iphone   # or XcodeBuildMCP list_devices
```

**If not paired:** generate a code and have the owner enter it on the phone
(**Profile → Trusted Machines → Add a machine → Pair over relay**). Codes expire ~5 min —
generate and use immediately.
```bash
~/.lancer/bin/lancerd pair        # prints a 6-digit code + relay URL; also a QR
```
⚠️ Run `lancerd pair` **exactly** — never `lancerd pair --help` (the binary doesn't recognize
`--help` and silently runs a real re-pair against `~/.lancer`, orphaning the current pairing;
this happened on 2026-07-15). Generating a new code replaces the pairing identity and orphans
any phone on the previous code.

**To rebuild + reinstall on the device** (XcodeBuildMCP, from the branch under test):
```
session_set_defaults { projectPath: ".worktrees/integration-night/Lancer.xcodeproj",
  scheme: "Lancer", deviceId: "<Roshan's iPhone udid>", bundleId: "dev.lancer.mobile",
  derivedDataPath: "/tmp/device-build-dd" }
build_device { platform: "iOS" } → get_device_app_path → install_app_device → launch_app_device
```

---

## Part C — Step-by-step test script

> Convention: **▶ Do** = the action, **✅ Expect** = pass condition, **✗ If it fails** = the
> triage move. Do the **core loop (§1–§4) first** — those are the publish gates. Feature
> checks (§5) can be done in any order after.

### §1 — Pairing & connection (gate: the app can reach your Mac)

1. **▶ Do:** On the phone, open Lancer → Profile → Trusted Machines.
   **✅ Expect:** your Mac listed with a green **Connected** status.
   **✗ If it fails:** confirm the daemon log shows `paired with phone` after your last code;
   re-pair with a fresh `lancerd pair` code. An orange/disconnected dot = the phone restored an
   empty pairing; re-pair.

### §2 — First-run onboarding (#130) — only visible on a fresh install

2. **▶ Do:** Delete the app and reinstall (or launch a fresh install) **without** the
   `-onboardingSeen YES` arg.
   **✅ Expect:** a welcome screen (one-line "what Lancer is", an autonomy **caution-tier
   picker** with 3 options, a **"Pair your Mac"** primary CTA in warm-orange, and a "Set up
   later" skip). Picking a tier + Pair opens the real pairing sheet; the pairing sheet shows a
   **progress spinner while connecting**.
   **✗ If it fails / it's skipped:** onboarding is gated by an AppStorage `onboardingSeen`
   flag; a prior install sets it. This is expected on an already-used device — not a bug.

### §3 — Dispatch → approval → follow-up (THE core loop, publish gate B10)

3. **▶ Do:** On the phone, from Workspaces, tap the composer pill, pick your repo +
   Claude Code, type a **low-risk** prompt like: `List the files in the current directory, then stop.`
   Send it.
   **✅ Expect:** the run starts; when the agent hits a gated tool you get an **approval card**
   (in-thread and/or a push notification). The daemon log shows `sent approval … over relay`.
4. **▶ Do:** Tap **Approve** on the phone.
   **✅ Expect:** the agent unblocks and continues within a couple seconds; the run completes;
   the transcript shows the result.
5. **▶ Do:** In the finished thread, type a follow-up: `Now count how many .swift files there are.`
   **✅ Expect:** it continues the **same** conversation (not a new one) and completes.
   **✗ If any of §3 fails:** see `docs/LIVE_LOOP_RUNBOOK.md` Triage — map the symptom (no
   approval arrives / approve doesn't return / follow-up forks a new thread) to the exact
   file. Capture the daemon log window and the phone os_log.

### §4 — Emergency Stop (#135, publish gate B11b) — NEW tonight

6. **▶ Do:** Start a longer run (e.g. `Read every file under Sources/ and summarize each.`).
   While it's actively working, go **Settings → (governance section) → Emergency Stop** and
   confirm the destructive dialog.
   **✅ Expect:** a confirmation dialog that states exactly what it does; on confirm, **all
   runs stop** and the UI reports the **stopped-run count**. The daemon stops dispatching.
   **✗ If it fails:** Emergency Stop calls the existing `agent.emergencyStop` RPC over SSH or
   the relay `agentEmergencyStop` mirror. It is **fail-closed** — it only reports success on a
   decoded `emergencyStopped == true`. If it errors, the error is shown (never a fake success).
   Note: this build is **stop-only** — there is no in-app "re-enable" (no client-visible clear
   RPC exists yet); re-enabling is a daemon-side concern. That's expected, not a bug.

### §4b — Push while the app is CLOSED (publish gate C2)

7. **▶ Do:** Fully close Lancer (swipe it away). Trigger a gated action again (dispatch from
   another surface, or have an agent hit a gated tool).
   **✅ Expect:** a **push notification** arrives on the lock screen with a **redacted** summary
   (risk + host, **never** the raw command/paths). Approving from the notification unblocks the
   agent.
   **✗ If it fails:** the push-backend requires `APPROVAL_RELAY_SECRET` + App Attest env or it
   fails closed; confirm the deployed backend. The APNs alert body is redacted by design
   (#136 tests pin this).

### §5 — Feature checks (tonight's work; any order)

**§5.1 Composer morph (#120).** ▶ On Workspaces, tap the "Plan, ask, build…" pill.
✅ It **expands in place** into the full composer card (grows upward over the list, keyboard
rises with it) — **no** separate drawer/sheet sliding up with a grab handle. Swipe down or tap
outside collapses it back to the pill. ✗ If a detached sheet with a grabber appears, the old
path is still active — check `WorkspacesView` doesn't present `.sheet` for the composer.

**§5.2 Thread-list rows (#121).** ▶ Open All Repos / a repo thread list.
✅ Rows show green/red **diff counts**, a relative timestamp, and an **unread dot** on threads
with new activity; desktop-CLI rows show **Connected/Disconnected**; the newest row shows a
one-line preview. ✗ If rows look bare, the metadata hydration didn't populate — check
`WorkspaceRepoCatalog` diff-stat source.

**§5.3 Review sheet (#122).** ▶ In a thread with changes, tap the floating **"Review +X −Y"**
pill.
✅ The review sheet shows a totals header, a **"PR not opened yet"** hint card (when no PR
exists), a **PR actions menu** (Open in GitHub / Open PR / Close PR — some disabled until the
backing RPC exists, with a footnote), and the changes card caps at **3 files with "N more"**.
✗ If the pill still says "N files", the copy change didn't apply.

**§5.4 Transcript cards (#123).** ▶ Run an agent that edits files, makes a to-do list, and
emits a markdown table.
✅ Between turns you see a compact **"Worked Ns · Edited N files · +X −Y"** summary row; a
**to-dos checklist** card with checked/struck items and "m/n"; markdown tables render as real
**grids** (not raw pipes). ✗ If tables show `| a | b |` text, the table parser didn't engage.

**§5.5 Background tasks (#124).** ▶ While a run has active shell/tool calls, look above the
composer.
✅ A **"N running tasks"** pill appears; tapping it opens a **Background tasks sheet** with a
Running section (title/type/elapsed) and Finished section. The live-thread nav bar shows the
**session title + repo** (not the generic "Chat"). ✗ If there's no pill during active work,
the running-tool count isn't binding.

**§5.6 Siri (#125).** ▶ Settings should now permit Siri (NSSiriUsageDescription present). Try
"Hey Siri, how many agents are running in Lancer?" (device only).
✅ The AgentStatusQueryIntent runs and Siri speaks a status dialog. ✗ Note: the automated
live-execution test is **device-only** — iOS 27 **simulator** rejects AppIntents execution for
all sim bundles (linkd "Unable to get teamId"), so sim testing this is expected to fail; use a
real device.

**§5.7 Decrypt fix (#127).** ▶ On the Mac, have a real Claude Code desktop session that used
extended thinking (any recent session with "thinking" blocks). In the app, open All Repos and
tap that **Desktop**-badged session.
✅ The transcript **opens and renders** — **no "Decryption failed"** error. ✗ If you still see
"Decryption failed", the SessionMessage.Role decode fix isn't in this build (confirm you're on
the integration branch).

**§5.8 Fake-control removal (#129).** ▶ Look at the composer(s) and Profile.
✅ **No microphone icon** on the composer pills (they were non-functional); Profile **Help**
row opens **GitHub Issues** in the browser. ✗ If a mic is still shown, the removal didn't apply.

**§5.9 Mid-run feedback + permission pill (#131).** ▶ Start a run; while it's actively working,
type a message in the composer and send.
✅ Instead of a disabled bar, your text is **accepted and queued** (shown as pending); when the
current turn finishes, it's **sent as the next follow-up automatically**. A **permission-mode
pill** (autonomy preset, e.g. "Balanced") is visible and tappable to change the preset. ✗ If
the bar is disabled mid-run, this build predates #131.

**§5.10 Empty/loading/error honesty (#133).** ▶ Force conditions: open the app offline
(loading/failed), open a repo with no threads (empty), kill the daemon and refresh.
✅ You see **distinct** states — a spinner while loading, an **inline retry banner** on
failure, and a genuine empty placeholder when there's no data (not all three collapsed into a
blank screen). ✗ If a failed fetch looks identical to empty, the state plumbing didn't apply.

**§5.11 Thread-list filters (#134).** ▶ On the thread list, tap the **filter/customize** toolbar
button.
✅ A **Status filter** sheet (Show All + per-status incl. Unread), a **Source filter** (phone
vs Desktop origin), and a **Customize sheet** (group by Recency/Repo, toggle diff-stats /
last-updated on rows). Toggles actually filter/regroup the list and persist. ✗ If there's no
filter entry point, #134 isn't in this build.

**§5.12 Policy editor & audit feed (#135).** ▶ Settings → policy editor; Settings → audit feed.
✅ Policy editor shows current rules + a YAML edit field that **saves** (validation errors
surfaced); audit feed shows a **read-only** list of recent audit entries. ✗ These are SSH-
transport features — on a relay-only pairing they should **error clearly**, not hang.

---

## Part D — Reporting results

For each section, record: PASS / FAIL / N-A, and for any FAIL paste the exact symptom + the
daemon log window (`~/.lancer/lancerd.stderr.log`) and, if a UI defect, a screenshot. File
results as a dated note under `docs/test-runs/` and add one line to `docs/CHANGELOG.md`.
The publish gates are §3, §4, §4b — those must PASS on a physical device before shipping.

**Known-accepted limitations (do not file as bugs):**
- Siri live-execution automated test is device-only (§5.6).
- Emergency Stop is stop-only, no in-app re-enable (§4).
- PR-actions menu items are disabled where no backing daemon RPC exists yet (§5.3).
- CloudKit two-device sync is unverified (needs a second Apple device).
