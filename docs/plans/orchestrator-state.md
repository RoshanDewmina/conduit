# Orchestrator state — Fable swarm dashboard

## ⚡ 2026-07-16 ~17:22 ET — auth-preflight FIXED + phone Hi launched (PR #145)

- **Merged:** PR #145 → `origin/master` `1a51329b` (probe 35s, boot warm, shim-excluding resolve, launchd PATH).
- **Host proof:** `conversation-append-launched allow` @ 21:19:07Z.
- **Phone smoke:** `"Hi"` → `conversation-append-launched allow` @ 21:20:25Z (no auth-preflight deny). Pair **149884** kept.
- **UI screenshot:** not captured (physical idb unavailable).

## ⚡ 2026-07-16 ~17:20 ET — auth-preflight fixed on host; phone smoke needs owner send

- **Root cause:** launchd cold `claude auth status` ~13s vs 20s probe budget → `conversation-append-auth-preflight` deny on `"Hi"` @ 21:05:24Z while interactive Claude was logged in.
- **Fix branch:** `fix/auth-preflight-cold-probe` — timeout 35s + boot warm + shim-excluding resolve + launchd PATH in plist; `go test ./...` green; host installed+reloaded.
- **Auth proof:** audit `conversation-append-launched allow` @ 21:19:07Z (RPC); `agent.status` `loggedIn:true`.
- **Pair:** code **149884** kept (no remint); doctor relay **confirmed** after reload.
- **Smoke:** phone send still **BLOCKED** on owner tap (idb cannot drive physical UDID); app foregrounded via `devicectl`.
- **App binary:** still master `ec3565f7` on phone — daemon-only fix.

## ⚡ 2026-07-16 ~17:05 ET — Lane C4 PARTIAL (pairing harness blocked; Audit PASS, FX5 PASS)

Sweep tip `671047a7` (C4 run). Evidence: `LC4-report.md` + `screenshots/LC4-*.png`. Daemon never
`paired with phone` → #7 chain ungraded (**not disproven** — harness pairing gate). Lane P: Audit
**PASS** relay; Policy **PARTIAL** (picker + stale SSH error — fix branch `fix/policy-stale-ssh-error`).
FX5 **PASS**. #10 FAIL on C4 was pre-FX10 tip; **FX10 `5a3fce93` on `origin/master`** — live re-proof
owed on owner phone. C4 retry needs single-session harness + pairing gate. Owner re-pair in progress.

## ⚡ 2026-07-16 ~16:50 ET — master `fbc85191` includes FX10; phone reinstalled; smoke BLOCKED on pair

- **`origin/master`:** `fbc85191` (PR #140 sweep + PR #141 FX10 `5a3fce93` + dogfood docs).
- **FX10:** YES on master — relay artifact mirror for background-tasks pill.
- **Phone install:** SUCCEEDED — `/tmp/lancer-device-dogfood-dd/Build/Products/Debug-iphoneos/Lancer.app` on `557A7877-…`; app launched.
- **Re-pair:** code **`347051`** minted post-install; **unconfirmed** — owner must Connect on phone (`DOGFOOD_SMOKE.md`).
- **Smoke:** pair/send/approve **BLOCKED** on owner tap; GAP #10 FIXED (code) / live owed.
- **C4:** may still hold Simurgh `lease-197` (isolated `/tmp/sweep-C4`) — do not steal.

## ⚡ 2026-07-16 ~16:40 ET — master has sweep (#140); folding FX10 + phone reinstall

- **`origin/master` (pre-FX10 push):** `99fd4526` (PR #140 = sweep tip `fe450949`).
- **FX10:** `5a3fce93` (`fix/background-tasks-pill`) merged onto master line in `docs/dogfood-smoke-2026-07-16` @ merge commit pending push — relay `lancerE2EArtifact` → `RelayArtifactIngest`.
- **Phone:** prior install was `b8bb778c` **without** FX10; rebuild+reinstall via `/tmp/lancer-device-dogfood-dd` IN PROGRESS.
- **Re-pair:** production code **`300552`** minted (replaced stale `310440`); still **unconfirmed** — owner must enter code on phone (C4 isolated at `/tmp/sweep-C4`, safe).
- **Smoke:** `DOGFOOD_SMOKE.md` — pair/send/approve **BLOCKED** on owner tap; launch PASS earlier.
- **GAP #10:** FIXED (code) / live owed.
- **C4:** still may use Simurgh `lease-197` — do not steal.

## ⚡ 2026-07-16 ~16:35 ET — owner ordered merge→master + phone dogfood (supersedes C4-wait autonomy stop)

**Sweep tip:** `integration/2026-07-16-untested-sweep` @ `b8bb778c` (+ docs hygiene commit pending).  
**Worktree:** `.worktrees/untested-sweep-2026-07-16`.

- **Wave 1 MERGED** (FX7 + FX5 + Lane P) on tip; unit gates previously green (`go test ./...`; `swift test` 781+62+13).
- **Owner directive (16:29 ET):** push + merge integration → `master`, install latest on physical iPhone, start dogfood. C4 live re-proof may continue in parallel on Simurgh `lease-197` — do not steal that lease; device build uses `/tmp/lancer-device-dogfood-dd`.
- **Merge-to-master:** IN PROGRESS (this session).
- **Dogfood:** next after `origin/master` tip confirmed + device install.
- **#10 fx10-bg-tasks:** leave in-flight worktree alone (not green/committed).
- **Owner re-pair:** still owed if production slot `310440` unconfirmed — only after confirming C4 will not fight the single relay slot (or document owner pairs after sim quiesces).
*(Superseded by 16:40 FX10 fold + `99fd4526` master merge above.)*

## ⚡ 2026-07-16 ~16:20 ET — Wave 1 MERGED + Simurgh preflight green; Lane C4 IN FLIGHT

**Sweep tip:** `integration/2026-07-16-untested-sweep` @ `7707e4fa` (`.worktrees/untested-sweep-2026-07-16`).

- **Wave 1 MERGED @ `7707e4fa`:** FX7 (`543566ba` needsApproval→awaiting) + FX5 (`2a872e1e` Connect above keypad) + Lane P (`7707e4fa` relay audit tail + coarse permission mode). Sentry `Package.resolved` pin stripped (`faeb80c9`).
- **Unit gates green on tip:** `go test ./...` ok (lancerd/policy/terminal); `swift test` 781+62+13.
- **Simurgh wave-1/2 @ `85f3907`:** daemon UP; `simurgh doctor` all ok; `simurgh exec lease-196 -- echo ok` → `ok`. Route long xcodebuild via `simurgh exec <lease> -- …`; isolate daemons with `LANCER_STATE_DIR` only (keep passwd `HOME`).
- **Lane C4 IN FLIGHT:** live sim re-test post-Wave-1 — #7/#8/#9/#17/#23 + #2/#3 Policy/Audit over relay + FX5 keypad screenshot + #10/#14 recheck + #1/#11/#18 harness retries if time. Evidence → `LC4-report.md`.
- **Owner re-pair still owed** (incident from C3 bare `lancerd pair`; L6 device pass owner-gated).
*(Superseded by 16:35 owner merge+dogfood directive above — C4 may still finish in parallel.)*

## ⚡ FULL-APP NIGHT TEST — 2026-07-15 ~22:40 ET

**Workspace:** `master` @ `ba73c130` (not on integration checkout). Reviewable tip still
`origin/integration/2026-07-15-night` @ `b17b6172` (PR #132 OPEN).

**§3 status: PARTIAL — NOT PASS (publish gate B10).**
Owner Approved in-app; audit has decide; hook `exit 0` **not** proven.

```
22:32:29 dropped approval 35b604b5-… — relay client not paired
22:33:33 paired with phone; re-sending 1; sent approval 35b604b5-… over relay
audit approve 35b604b5-… @ 2026-07-16T02:35:20Z
hook terminal ended 02:34:32Z exit_code=unknown (before approve)
queue pending=0
```

**A) Approval surface — deliberate machine-scope + missing home UI (not "you opened wrong thread" alone):**
- `RelayApprovalIngest.swift:21-32,39` — no runId on wire; keyed by machine; Inbox "system of record" in comment but Workspaces shell has no Inbox nav
- `LiveThreadView.swift:181-184` — card only when live thread open + `activeMachineID`
- Push: `server.go:1669-1673` needs in-memory `s.device`; restart cleared it; `e2e_router.go:80-82` drop when unpaired; resend `e2e_router.go:40-58` is WS-only (no APNs). Silent Mode secondary. Historical push-backend 401/500/503 in stderr (earlier).

**B) "Bash Bash:" + wall of prose — real gap on master AND integration (not night-only regression):**
- `claude_transcript_adapter.go:320-336` Text=`"Bash: cmd"` + ToolName=`Bash`
- `LiveThreadTranscript.swift:120-130` prepends `toolName+"\n"` → duplicated label
- `LiveThreadView.swift:576-592` observed turns without event artifacts → `ChatMarkdownBody` only (not BlockRenderer/ToolCallChip)

**Recommend:** stop §5 chat dogfood; file P0s for A+B. Optional §4 Emergency Stop only. Do not mark B10/C2 PASS.

**Digest:** merged-N/A / in-flight: diagnosis / blocked: P0 UX / next: owner decide fix-first vs §4 / decisions-needed: continue gates?

---

## ⚡ SESSION 8 2026-07-15 — five-stream reliability brief (owner switches to phone daily-driving today)

Brief: `docs/plans/2026-07-14-fable-handoff-attachments-latency-PASTE.md`. Master @ `292525b7`
(verified matches origin at session start). Owner decisions taken this session (AskUserQuestion):
**Stream 1 proof = sim-first (isolated daemon over real Fly relay) then short owner device pass;
Stream 4 = per-dispatch "Full tools" toggle, strict/fast default — not blanket ship.**

- **Stream 1 (10× reconnect proof) — FAILED at cycle 2/10; ROOT CAUSE FOUND (fifth-fix
  skepticism vindicated).** Method that finally worked: XCUITest `ReconnectCycleUITests`
  (uncommitted, main checkout LancerUITests/ — KEEP as permanent regression harness; HID/idb
  taps can't drive SwiftUI on this sim, documented gotcha). Cycle 1 passed; cycle 2 Retry.
  **Root cause, evidenced BOTH directions:** session key is static across reconnects
  (deriveSessionKey e2e_client.go:340-346 uses only static pairing keys — the 2026-07-04 open
  P2 "no epoch nonce") + replaySequencer (e2e_crypto.go:156-185) is a bare monotonic counter
  reset on peer_joined ⇒ a stale in-flight old-generation frame (still decryptable) arriving
  AFTER the reset is accepted, re-poisons `last` to a high value, and every legitimate
  new-generation frame (seq 0..) is rejected — one direction deaf until the next peer_joined.
  Daemon-side proof: /tmp/s1-reconnect/lancerd.stderr.log rejected phone seq=0..29 for 5 min
  post-restart (10:56→11:01). Phone-side proof: sim os_log 11:01:50 "replayed or out-of-order
  sequence 0,1,2…" while audit.log shows the cycle-2 send DID launch (2 UITest
  conversation-append-launched entries) — phone deaf to the reply ⇒ Retry. ALL prior fixes
  (#111 seq resets, append correlation) were symptom patches of this. **Fix lane IN FLIGHT:**
  `.worktrees/relay-generation-guard` (fix/relay-generation-guard, Sonnet): generation-tagged
  seq envelopes (random 16B gen id minted per reset; receiver tracks currentGen+seenGens;
  stale-generation frames rejected WITHOUT touching the counter; legacy no-gen peers keep old
  behavior — co-deploy iOS+daemon closes the hole, no relay/backend change). Then re-run the
  10-cycle UITest on the fix build. Evidence dir: `docs/test-runs/2026-07-15-reconnect-10x-sim/`.
- **Stream 2 (Agents continuity)** — CODE DONE, gates green, unmerged. Diagnosis (Explore):
  p1-agents-direct-open DID merge (#94/c49ec4f5); Bug A = blank thread on adopt-with-empty-
  transcript (ShellLiveBridge.swift:270-288 set .idle on 0 messages); Bug B =
  `!hasEverSucceeded && consecutiveFailures>0` bypassed the 2-failure degrade threshold
  (RunningAgentsMapping.swift:209) + first-tick false failure during hydration
  (RunningAgentsSection.swift:154). Fix on `fix/s2-agents-continuity` @ `00485128` (Grok impl,
  Fable-reviewed): degraded copy only at ≥2 failures, "No agents running" after first success,
  "Checking for agents…" pre-success, transitional machines don't burn failure budget, new
  `.adoptedNoHistory` sendState + visible placeholder. Verified by orchestrator re-run:
  swift build ✓, RunningAgents 10/10 ✓, LiveThread 12/12 ✓, app-target BUILD SUCCEEDED
  (worktree needs `xcodegen generate` first — .xcodeproj not checked in). ui-risk → owner
  eyeball batched with device pass; then merge.
- **Stream 3 (attachment integration)** — MERGE DONE + REVIEWED, gates green, unpushed.
  `feat/attachment-integration` @ `72fd250e` = master merged in; only conflict dispatch.go
  launchConversationTurn, resolved to documented 6-step order (clean policy+digest → policy →
  attachment verify → ensureClaudeAuth → vendor manifest → launch). Fable full-diff review of
  dispatch.go + e2e_router.go + conversation_rpc.go: PASS (hardening intact; nits: swallowed
  ensureAttachmentRoot err weakens root redaction to per-path placeholders; one unreachable
  error path lacks audit). Gates: go vet/test/-race 514 PASS, full swift test 732+62+13 (no
  Keychain collision), app-target SUCCEEDED, AttachmentPreviewUITests 2/2. REMAINING owner-
  gated: co-install daemon+app pair on phone + live proof (chip .done, PDF, multi, persistence,
  Retry same clientTurnId, no hostPath in UI/AX).
- **Stream 4 (latency toggle)** — IN FLIGHT, Sonnet: `.worktrees/s4-mcp-toggle`
  (`feat/s4-fulltools-toggle` = master + cherry-picked 9992701f strict-mcp perf commit).
  `fullTools` bool threaded append/dispatch→argv builders; absent→strict (backward compat);
  composer toggle (Claude-only, a11y id composer-full-tools-toggle). Sensitive → Fable
  full-diff review on completion.
- **Orca second opinion** (owner-requested): `docs/product/2026-07-15-orca-reconnect-mcp-port-map.md`.
  Validates strict-by-default+toggle (Orca always-loads only because CLIs are resident).
  Post-proof hardening queue: send-after-connected gating, send-time desync self-heal,
  foreground probe + backoff reset (task #7).
- Worktrees added this session: `.worktrees/s2-agents-continuity`, `.worktrees/s4-mcp-toggle`.
- Merge order once Stream 1 verdict lands: s2 → attachment-integration → s4 (dispatch.go
  overlap s3/s4: s3 touched launchConversationTurn, s4 touches argv builders — re-gate after
  each merge).

## ⚡ SESSION 7 2026-07-14 — attachment lanes to feature-complete (WIP only); P0 relay/auth phone proofs still owner-gated; beta NOT READY

- **master HEAD `e1309f95`** ("fix(ios): hydrate imported assistant replies"), **10 commits
  ahead of `origin/master`, unpushed**: e1309f95, 53ed9eea, 7df8b831, 5850df3d, d46eb716,
  67b26ef6, 28169869, a566425f, dcb2d553, 4a6677b7.
- **P0 blocker unchanged — relay/auth phone proofs still owner-gated, still open:**
  - `fix/relay-append-correlated-resume` (`.worktrees/relay-append-correlated-resume` @
    `292525b7`, clean, `go test ./...` passes) **NOT merged to master** — gated on the owner
    performing, on a physical phone: logged-out fail-closed proof → `claude auth login` →
    ≥16s post-rekey first-append proof with no duplicate/no Retry.
  - `fix/claude-auth-ttfo` (`.worktrees/claude-auth-ttfo` @ `d9ee016c`, clean) is a subset of
    the above branch, same gate.
  - **Live auth ambiguity, still unresolved:** `~/.claude/.credentials.json` is missing but
    `claude auth status --json` reports `loggedIn: true` — contradiction, treat as UNPROVEN
    per existing project convention.
  - Installed daemon `~/.lancer/bin/lancerd` (pid 84648, sha256
    `cf50089bbf6b6af31f08dcd6df5f43fb172329d8c7e98fde3472f755c300ee99`) matches the
    relay-append-correlated-resume build. No `contentDigest` strings in it — attachment
    hardening is NOT installed on the running daemon.
- **Attachment work driven to feature-complete this session (multiple REQUEST_CHANGES review
  cycles), but WIP-only — not integrated, not gated, not merged to master:**
  - `feat/attachment-daemon-dispatch` (WIP commit `6b5329fe`) — server-issued `contentDigest`,
    content-addressed objects, TOCTOU rehash, path/symlink containment, event redaction.
  - `feat/attachment-ios-ux` (WIP commit `75445047`) — iOS consumes server id/path/
    contentDigest with stable `clientTurnId` retry.
  - Both are mutually compatible; new integration worktree `.worktrees/attachment-integration`
    on `feat/attachment-integration` (off `e1309f95`) is merging both — **in progress, not
    yet complete, not yet gated, not yet merged to master.**
- **External handoff bundle** for today's session at
  `/Users/roshansilva/Downloads/lancer-beta-handoff-2026-07-14/` (README,
  BETA_READINESS_HANDOFF.md, NEXT_AGENT_PROMPT.md, REPO_STATE.md, SOURCE_PATHS.md, patches,
  git bundle) — reference it, don't duplicate its content here.
- **Verdict: TestFlight beta NOT READY.** P0 (auth/relay phone proofs) is owner-gated and
  blocks merging auth/relay to master. P1 (attachment integration) is being prepped in
  parallel in worktrees only — not blocking, but also not merging to master until P0 clears,
  per the project's co-deploy rule.

## ⚡ SESSION 6 2026-07-14 ~02:00 — #114/#118 merged; pairing-durability SUPERSEDED; P1b lane live

**Context at start:** a Codex session (not this orchestrator) had already merged #115
(preserve replay state on invalid re-key) and **#116 (Fly relay cutover — INCLUDING the full
pairing-durability feature: ConfirmedAt persistence, writeRelayPairingReplacing,
confirmed code_expired re-register, everConfirmed restore + withRelayPairingLock file lock)**.
Owner confirms phone is on the post-#116 build, paired to Fly, working.

- **#114 MERGED** (WP-P1a display filter + a second commit fixing the fetch-on-open bug:
  list summaries were poisoning `lastHostSeq` — new `hydratedEventCursor` resumes from the
  highest CONTIGUOUS local event seq; daemon seqs verified contiguous-from-1, never deleted).
  Stage-4 blocking finding was process-only (no sim evidence); owner authorized merge, device
  re-dogfood is the verification. Backlog minors: `$0.turnID!` force-unwrap ×2, 10k event cap
  in ThreadDetail `hasAssistantArtifacts`, lastHostSeq-vs-baseSeq decoupling (speculative).
- **#118 MERGED** (approval-queue: single retirement point in `applyDecision` after resolve
  succeeds; delivery no longer clears the durable queue; auto-allow-no-client retires too).
  Fable full-diff review: retire hook fires only post-resolve, outside store lock (no
  getQuotaGuard-style nesting); fail direction safe (failed removal → duplicate card, never a
  lost approval). Gate re-run by Fable on PR+master merge: `go test ./...` ok (45s).
- **Pairing-durability worktree DELETED as superseded** — content-diff vs master showed only
  older variants of what #116 landed (branch had no lock file, pre-#115 seq handling); doc
  `2026-07-12-pairing-durability.md` is on master. No PR needed. Recurring-bug lane
  "pairing durability" = CLOSED by #116.
- **Docs committed** (07-13 PASTE brief, owner-asks, post110 blockers, appstore recap, audit
  HTMLs, dogfood-log 07-13 entry). `simurgh/` intentionally untracked (separate project,
  owner call 2026-07-14).
- **WP-P1b IN FLIGHT** — `.worktrees/p1b-live-review` (`feat/p1b-live-review-wire`),
  gpt-5.3-codex-high, spec `spec-p1b.md`: phone-side only; daemon repo.* relay arms already
  exist (e2e_router.go:687-760). Bridge helpers must be 15s-bounded (#111 rule).
- **WP-P1c QUEUED behind P1b** — same write-set files (LiveThreadView/ThreadDetailView);
  serialize, do not parallel-dispatch.
- **G3 pill absence** on POST-110 dogfood attributed to the #111 deafness bug — verify on
  device, no code lane unless it reproduces post-fix.
- **Owner-gated queue:** re-run `docs/plans/phone-test-session4.md` on the current build
  (now vs Fly relay) + R1/R2 ×10 + Agents→Mac continuity + APNs lock-screen + emergency stop.
  Note: hourly Cloud Run websocket ceiling may be GONE on Fly — observe reconnect cadence
  in `lancerd.stderr.log` during dogfood.

## ⚡ PAIRING DURABILITY 2026-07-12 ~18:55 — one-time onboarding (fix/pairing-durability)

**Owner bar:** pairing is one-time onboarding. Do **not** expect re-pair on laptop reboot,
LaunchAgent restart, lancerd binary replace, or phone app upgrade. New codes only for first
onboarding, explicit `lancerd pair` / unpair, or true key/identity loss.

**Today's re-pair was abnormal:** logs show the confirmed production code was stomped
at ~17:13 by a **localhost** test relay (`ws://127.0.0.1:54xxx`), then a cascade of test
pairings, then restore/re-pair. Not REL-1 remint of a confirmed phone; not POST-110
install wiping identity. See `docs/plans/2026-07-12-pairing-durability.md`.

**Fix branch:** `.worktrees/pairing-durability` (`fix/pairing-durability`) — persist
`confirmedAt` in `~/.lancer/relay-pairing.json`, load into `everConfirmed` across restart,
refuse silent overwrite of confirmed identity (explicit pair uses `writeRelayPairingReplacing`),
confirmed `code_expired` re-registers same code (daemon+phone) instead of remint/wipe.
Live file stamped `confirmedAt` for the restored code (identity unchanged). Do NOT run bare
`lancerd pair` while phone holds the slot.

## ⚡ SESSION 5 2026-07-13 ~17:15 — B1/B2/B3 ROOT-CAUSED (one protocol bug); PRs #111 #112 up

**Root cause of ALL THREE POST-110 P0s (B1 stuck-Working, B2 Agents-unreachable, B3
attachment-spinner) + missing G3 pill + the ≥4-session "stuck after reconnect" recurring bug:**
Cloud Run drops the daemon's relay websocket **hourly** (`lancerd.stderr.log`: EOF 00:57,
01:57 … 15:35:21, re-pair 2s later). Daemon `peer_joined` resets replay counters
(`e2e_client.go:358-360`); phone's `peer_joined` did NOT (`E2ERelayClient.swift` — resets only
lived in connect()/disconnect()/handleDisconnect). After any daemon-side-only reconnect the
phone rejects EVERY inbound frame as "replayed or out-of-order" **forever** — phone→daemon
still works, so dispatches execute on the Mac while the phone is deaf. Proof: "Hi" turn in
`~/.lancer/conversations.sqlite` is `exited` 19:33:22Z while phone stayed Working….
Aggravator (B2 permanence): `relayListSessions` + 4 other bridge RPCs had NO timeout — one
dropped response wedged `RunningAgentsSection.pollLoop` for the app's lifetime.

- **PR #111** `feat/relay-rekey-seq-reset` — phone seq reset on peer_joined/peer_left + 15s
  bounded waits on the 5 unbounded RPCs + regression tests. Codex 5.3 High implemented; Fable
  full-diff reviewed (sensitive). Gates re-run by Fable: swift build ✓, swift test 681+62+13 ✓,
  go test ✓. CI pending at handoff.
- **PR #112** `feat/w0-device-dogfood-fixes` (WP-0) — vendor picker (Codex/OpenCode) + Attach
  `+` + fixture-review-pill removal + daemon task-notification skip + session-4 evidence.
- **PR #113** `feat/p1a-tasknotification-display-filter` (WP-P1a, stacked on #112) — iOS
  display filter mirrors daemon `isObservedWrapperUserText`; no XML bubbles / orphan
  "(no reply text)" on legacy threads. Gates re-run by Fable: 687+62+13 tests ✓.
- **CI green on #111 + #112 (all 4 checks incl. build_sim). MERGES ARE OWNER-GATED**
  (#111 sensitive relay protocol; #112/#113 ui). Merge order: #111 → #112 → #113
  (retargets automatically). Then: device rebuild + owner re-run
  `docs/plans/phone-test-session4.md` + R1/R2 ×10 + Agents→Mac session.
- **Pairing-durability worktree**: committed as WIP snapshot on `fix/pairing-durability` —
  **collides with #111 write-set** (E2ERelayClient.swift, e2e_client.go); rebase + Fable review
  AFTER #111 merges, then PR.
- **Model slugs (verified `cursor-agent models`)**: NO "GPT-5.6" exists. Hard lane =
  `gpt-5.3-codex-high` (used for #111). Grok = `cursor-grok-4.5-high`.
- **Fly.io relay migration in progress in main tree (NOT committed, NOT mine):**
  RelaySettings.swift → `wss://conduit-push.fly.dev`, push-backend Dockerfile/fly.toml/
  entrypoint, project.yml, relay_install_helper.go. Owner-gated cutover — left untouched.
- **ENOSPC gotcha recurred**: disk hit 100% mid-gates (208MB free); cleared go-build cache +
  DerivedData → 23GB. Re-ran all gates after.
- **After #111+#112 merge**: device rebuild + owner re-run `phone-test-session4.md` + R1/R2 +
  Agents→Mac session. Then WP-P1a (iOS task-notification display filter), WP-P1b (live
  repo.turnDiff wire + G3 pill verify), WP-P1c (scroll/FR polish).
- Relay ops note for later: even with the fix, hourly re-keys cause ~2s blips; long-term the
  relay's 1h websocket ceiling is a cost/infra question (Fly migration may change this).

## ⚡ SESSION 4 ~18:50 — Codex/OpenCode phone vendor picker slice STARTED

**Owner ask:** why phone only shows Claude models; get Codex + OpenCode started.

**Root cause (not missing adapters):** daemon already has full Codex/OpenCode argv +
`installedAgents` RPC. Phone New Chat hardcodes Claude in `ShellLiveBridge` + Claude-only
`DispatchModelSelection`. Identity badges / hot-swap are queued separately
(`2026-07-12-account-hotswap-and-identity-design.md`). Plan note:
`docs/plans/2026-07-12-codex-opencode-vendor-picker.md`.

**Implemented (uncommitted on master — do not stomp relay / pair):**
- `DispatchVendorSelection` + `VendorPickerView` (composer Agent chip)
- `ShellLiveBridge.send` uses selected vendor; Claude-only model slug
- `RelayFleetHydration.refreshInstalledAgents` + AppRoot / composer fetch
- Tests green: `DispatchVendorSelection` + `DispatchModelSelection` (9 tests)

**Owner unblocks for live Codex:** `LANCER_CODEX_UNSAFE` unset — headless may hang without
safer argv (`--ask-for-approval never --sandbox workspace-write`) after smoke. Codex/Kimi
launch still escalates (no per-action hook). OpenCode uses CLI default model (`provider/model`
picker later).

**Next:** device build of this slice → New Chat → Agent → Codex/OpenCode dogfood; optional
safer Codex argv PR; identity badges lane still independent.

## ⚡ SESSION 4 CONTINUED 2026-07-12 ~18:20 — #110 merged; POST-110 device build in flight

**Merged this session (Fable session 4 + Cursor continuation):** #105 (scroll arrow + proof chips
+ fetch-on-open), #106 (G1 turn-diff RPCs), #108 (G3 live status pill), #109 (lane H context
attachments — Photos/Camera/Files → daemon drop dir → prompt paths), #107 (G2 Codex-1:1 review
sheet — turn/session diffs, file tree, line-comment→composer), **#110** (REL-1 relay robustness —
structured relay error codes + expiresAt · daemon auto re-mint on dead unconfirmed code · phone
`.codeExpired` stop-churn + TTL countdown · first-send readiness gate + single retry; merge SHA
`0e0b9eba`). CI fix: `nonisolated` on `E2ERelayBridge.firstSendRetryWindow` /
`isFirstSendRace` so iOS-gated unit tests compile under `build_sim`.

**Open PRs:** none blocking session-4 dogfood stack.

**Device builds (parallel agents — do not stomp):**
- **PRE-110:** `build/device-86b7a767/` — master pre-REL-1 (`86b7a767`), already installed on
  owner phone ~18:12.
- **POST-110:** `build/device-POST-110-0e0b9eba/` — master post-#110 (`0e0b9eba`); generic
  `iphoneos` build **SUCCEEDED** ~102s (log `/tmp/lancer-device-build-POST-110.log`); phone
  unavailable at install time — install when reconnected (see `OWNER_INSTALL.md` in that dir).

**Still owed:** install POST-110 on owner phone when connected → sim feature-drive on integrated
master (attachments + G2 review sheet + G3 status pill + REL-1 reconnect) → owner verify:
fetch-on-open pulled the 35-turn "Fix triple…" conversation? first send without Retry?

**New gotchas:** RelayMachineMigrationTests collide across CONCURRENT swift test runs in
different worktrees (shared macOS Keychain) — run LancerKit suites serially, one worktree at a
time · xcodegen generate + per-worktree XcodeBuildMCP defaults works fine for app-target gating
worktrees (~100s cold) · a PR can silently get NO CI run on first push — check `gh run list
--branch` and re-kick with an empty commit.

## PREVIOUS HANDOFF 2026-07-12 ~16:30 — session 3 end state (context full)

**Merged today:** #95–#104 (cwd/bucketing P0 ×4, backfill, long-transcript daemon+iOS, search-tap,
structured transcripts Z1, tool chips Z2). **OPEN: PR #105** (fix/scroll-arrow-hit-target) —
arrow visibility/tap (tail-marker onScrollVisibilityChange + two-hop scrollTo + 96pt tail spacer),
proof chips in BOTH views (ReceiptChipRow), Flight Recorder → ⋯ menu, composer lockRepo,
fetch-on-open (refreshThreadFromHost). All sim-gated except fetch-on-open live path (owner phone
holds the single relay slot — owner verifying). Merge #105 when CI green.

**Coded, NOT yet gated/PR'd (worktrees):**
- G1 `.worktrees/g1-turn-diffs` — committed, go gates green, jail reviewed → needs PR.
- G2 `.worktrees/g2-review-ui` — Codex-1:1 review sheet vs fixtures; needs my gates+review+PR.
- G3 `.worktrees/g3-live-status` — status pill + daemon events; needs gates (incl. dispatch.go
  additive-only check via vendor-cli-adapter-audit) + review + PR.
- H `.worktrees/h-attachments` — context attachments (owner P0), cursor-agent STILL RUNNING.
**Uncommitted worktree diffs must be committed before session end** (standing rule).

**Relay ops:** owner phone paired to the production relay; daemon = master post-#100
(`lancerd.bak-pre-p100`). NEVER run bare `lancerd pair` while owner holds the slot. Backend
project roshan-agent-f1c2466d, service conduit-push (australia-southeast1) — REL-1 evidence in
gap audit (silent code expiry / half-open sockets / slot churn, gcloud logs cited).

**Owner asks queued:** REL-1 relay robustness (tester blocker #1) · finish H · gate/ship G1-G3 ·
identity badges → hot-swap (`2026-07-12-account-hotswap-and-identity-design.md`) · terminal
phases (`2026-07-12-orca-terminal-port-map.md`) · "+" vs Add Repo dedupe · backfill paging >50 ·
Siri Phase 2 merge needs owner iOS-27 target call · dogfood-log habit.

**Session-3 gotchas (append-worthy):** `agent` CLI name is shadowed by grok — use `cursor-agent` ·
`&`-backgrounded dispatches die with the shell — use run_in_background per lane · `git stash pop`
in main checkout popped an ALIEN stash & contaminated a commit (reverted 5e664bc9) — never pop
without `git stash list` first · sim DB seeding: `get_app_container` + sqlite works for UI gates ·
ThreadDetail root ZStack overlays the follow-up bar (hit-test) · onScrollGeometry goes stale under
keyboard resize — use onScrollVisibilityChange · scrollTo across LazyVStack needs two hops.


## ⚡ HANDOFF 2026-07-12 ~12:10 — session 2: backfill + long-transcript lanes shipped (PRs #99–#101); hotswap/identity designed

**Merged this block (on top of #95–#98):**
- **#99** fresh-install backfill — the sync that mirrors the daemon ledger was gated on a local
  running turn (impossible on a fresh install); now unconditional. Owner-phone-proven: reinstall
  went from All Repos 1 → 50 with correct rows.
- **#100** daemon long-transcript import: 2MB cap now keeps the NEWEST end (+truncated flag);
  observed sessions segment into real turns at each user prompt (wrappers skipped, per-turn
  vendorSessionID = exact resume); attach uses the transcript ai-title. Live-proven: this very
  orchestrator session (5.6MB) re-attached as "Fix triple command-center rows with three-lane
  P0 cwd hygiene", **35 turns, 1036 events** (was: garbage title, 1 turn, 911 oldest-end events).
- **#101** iOS long-thread rendering: LazyVStack + recent-100 window ("Show earlier…"), NSCache
  markdown memoization + >256KB plain-text fallback, page-by-page fetch merge with honest
  partial-sync (.cloudStale) at the 20-page cap, and MAX() guard on last_activity_at (sweep major).
- Fan-out sweep findings: `docs/plans/2026-07-12-edge-case-sweep-findings.md` (7 backlog minors).
- Approved design (brainstormed w/ owner): `docs/plans/2026-07-12-account-hotswap-and-identity-design.md`
  — identity badges lane (ui) FIRST, then Claude account hot-swap (sensitive → Sonnet).

**Live state:** daemon = master post-#100 (`lancerd.bak-pre-p100` backup), owner code 116955.
The re-attached long conversation is the newest ledger row — owner phone backfills it on refresh.
**PENDING: final device install of the #101 build (phone was disconnected) + owner verification:
search "fix triple" finds the conversation; it opens segmented and scrolls smoothly.**

**Queue after that (owner-ordered):** ① context uploads + artifact rendering (both directions)
② reconnect-race reliability ③ identity badges ④ account hot-swap ⑤ terminal Phase 1–3
(`docs/product/2026-07-12-orca-terminal-port-map.md`) ⑥ "+" vs Add Repo dedupe · Proof card →
Flight Recorder · backlog minors.

## PREVIOUS HANDOFF 2026-07-12 ~10:45 — P0 CLOSED (PRs #95–#98 merged, dogfood-proven); new owner asks queued

**All four lanes merged to master (`33aa0fdd`):**
- **#95** lane T repo bucketing (Cursor grok; codex review found Home-label + badge/list mismatch, fixed; live sim gate: one command-center row + PONG round-trip).
- **#96** lane W daemon cwd hygiene (Cursor grok; Fable full-diff review caught resolveDispatchCWD-is-Stat-only → explicit IsAbs guard `a07cba25`; **live-proven post hot-swap: `restoreQueue: pruned 5 stale approval(s)`** — the empty-RunID ghosts).
- **#97** lane V chat-loop robustness (2 blocking review findings fixed `4fc63e18`, re-review approve; live gate: close-mid-run → new chat round-trips, Retry ×2 recovered real reconnect races, reopened thread shows real transcript).
- **#98** lane X tilde fix (owner phone showed 16/1/0 command-center rows on the merged build — added repo stored as `~/…` sandbox-expanded on iOS into a bogus root; `NSString.isAbsolutePath` counts `~` as absolute. Fixture reproduces exact phone state; review approve; owner phone reinstalled with this build).
- **Dogfood gate PASSED (owner's new done-bar, saved to memory):** agent dispatched FROM Lancer's sim composer fixed all 25 `SiriRelevanceCoordinator` warnings; Edit approval approved on the owner's physical phone; receipt + exit 0; committed `226f2307`.

**Relay ops state:** owner phone paired on **code 116955** (fresh — a sim-gate `lancerd pair` wiped the backend's in-memory 208937 registration; the owner's phone auto-retry against the dead code was ALSO what kept kicking the sim off, ~2s re-pair loop). Daemon binary = master post-#96 (`lancerd.bak-pre-p96` backup). Sim app stopped. ⚠️ NEW RULE: never run bare `lancerd pair` while the owner holds the slot — it replaces the pairing AND kills the old backend registration; `--help` is not parsed (it executed twice).

**New owner asks (2026-07-12, this session) — dispatch next, in recommended order:**
1. **Context uploads + artifact rendering** (composer Context sheet is affordance-only, `ContextAttachView.swift:132`; = readiness-audit gap #1, both directions). 
2. **Full terminal support** (owner reversed the 2026-06-30 deferral): phased plan in `docs/product/2026-07-12-orca-terminal-port-map.md` — Phase 1 re-wire existing block terminal (ui), Phase 2 lancerd-owned terminal sessions over relay (sensitive), Phase 3 mobile input kit (ui).
3. Proof card placement: receipt chip in chat, full card in Flight Recorder (decided, backlogged).
4. Verify Agents section populates on the owner's phone now that pairing is stable (feature exists: last-60 observed sessions, tap-to-continue via #94). If still "Machine unreachable" while connected → bug lane.
5. Readiness audit for the "full-time on Lancer" goal: `docs/product/2026-07-12-full-time-readiness-audit.md` (top gaps: uploads/artifacts ↔, first-send-after-reconnect race, diff review card, plan-limits #22, webapp preview).
**Reliability backlog (seen ×3 live today):** first send after a fresh pairing/reconnect races the relay re-key → "machine didn't respond"; Retry recovers. Root-cause lane recommended before terminal Phase 2 touches the relay.

Pre-existing backlog (#22–#28 owner-asks ledger) unchanged below.

## PREVIOUS HANDOFF 2026-07-12 ~09:00 — OWNER P0: duplicate command-center rows in Workspaces (3-lane fix in flight)

**Owner P0 (screenshot + owner's words "Multiple instances of command-center — make sure we can
only have one"):** Workspaces shows THREE command-center rows plus a "roshansilva" row. Confirmed
against `~/.lancer/conversations.sqlite`: cwd buckets split across `/Users/roshansilva/Documents/command-center`
(18), bare relative `command-center` (3), a `.claude/worktrees/hungry-ritchie-389bd0` subpath (1),
plus `/Users/roshansilva` (39), `/tmp` (8), empty string (1). Two independent root causes, both
audit-traced with file:line:
- **(a) app-side:** `WorkspaceRepoCatalog.swift` `deriveRepos`/`matchingRepoCwd` only buckets
  against ADDED repos — never absorbs worktree/relative/home-dir cwds into one root.
- **(b) daemon-side:** `conversation_rpc.go:122` (`conversationsAppend`) and
  `conversation_store.go` (`attachObservedSession`) persist relative/empty cwd BEFORE
  `resolveDispatchCWD` validates; `server.go:1555-1557` leaves `ApprovalEvent.RunID` empty for
  hook events with no in-memory run, so `restoreQueue` can never prune them.

**Three lanes, disjoint write-sets — specs rescued to
`docs/plans/2026-07-12-p1-repo-cwd-hygiene-specs.md` (commit `90c005ba`):**
- **Lane T** `fix/p1-repo-bucketing` (ui) — IMPLEMENTED by Cursor grok-4.5-xhigh in
  `.worktrees/p1-repo-bucketing` (6 files, +363/−70), UNGATED, UNCOMMITTED. Single
  `bucketKey(forCwd:)` everywhere + 6 smaller audited fixes. Gate: swift build/test →
  app-target build_sim → sim shows exactly ONE command-center row (count 22) → review → owner eyeball → PR.
- **Lane V** `fix/p1-chat-loop-robustness` (ui) — IMPLEMENTED same way in
  `.worktrees/p1-chat-loop` (10 files, +297/−95), UNGATED, UNCOMMITTED. ShellLiveBridge reset on
  dismiss (close-mid-run wedge P0), Retry re-dispatch, reopened-thread real transcript,
  no fake `.completed`, fractional timestamps, receipt-decode logging. Same gate; owner eyeball batched with T.
- **Lane W** `fix/p1-ledger-cwd-hygiene` (sensitive-adjacent: approval-ingest + RPC surface) —
  NOT YET DISPATCHED. Validate cwd via `resolveDispatchCWD` before persist; reject
  relative/empty in `attachObservedSession`; best-effort RunID backfill (never invent);
  `deriveTitle` wrap. Gate: go test/vet from daemon/lancerd + **Fable full-diff review**.

**Then:** ONE device build with all three; update STATUS_LEDGER + this file; verify one
command-center row on device/sim. Only then the owner-asks backlog (#22–#28) — this is a
same-phase P0 interrupt, not a pivot. **Rule reinforced:** commit lane output (even WIP) as soon
as its diff is stable — quota cutoffs stranded these worktrees once already.

## PREVIOUS HANDOFF 2026-07-12 ~00:20 — PUNCH LIST FULLY CLEARED (PRs 89–94 merged); device build ready, phone offline

**#94 merged** (Agents row → conversation directly; interstitial deleted; sim-gated with the
live orchestrator session's own transcript). CI note: the app-target job on #94 failed ONLY on
the known-flaky `waitForAnyConnected` test (deflaked once in #61; ConnectionStateStore untouched
by the diff; local app-target build + full suite green) — flake, not regression; deflake again
if it repeats. **Owner relay pairing RESTORED** (code 208937, daemon hot-reloaded + reconnected;
phone auto-reconnects via stable identity — no code needed). ~/.cursor/mcp.json restored ✓.
**Device build from master `c49ec4f5` INSTALLED + LAUNCHED on the owner's phone (2026-07-12 ~08:36); pairing auto-restored on code 208937 (stable identity, zero taps). ⚠️ One stale approval card on the phone ("git log", empty-RunID so #92's prune correctly kept it; agent process dead) — owner taps Deny once.** Owner review list: ① thread badges clear on
foreground ② receipt card + Proof Reel after a run ③ Flight Recorder rows in thread detail
④ Agents row opens the chat directly. Remaining owner-gated: APNs lock-screen co-test ·
emergency-stop verify · Cursor-dashboard plan-usage check (ledger #2).

**Routing confirmation (owner check 2026-07-12):** all five punch items were Cursor-dispatched
(lanes Q/S/R = grok-4.5-xhigh); Fable edits were confined to root-cause one-liners found mid-gate
(#90 optional field + verbatim-payload test; #93 hydration-wait, mirroring an existing pattern)
plus docs. Next parallel lanes per owner-asks ledger (~/Downloads/lancer-owner-asks-ledger-2026-07-11.md):
#22 plan-limits collector (⚠️ needs owner call: skip Cursor per-device for V1?) · #23 account
switcher (sensitive → Sonnet) · #25 bug reporting · #26 artifact rendering · #27 S27 lane ·
#28 cross-device proof — disjoint write-sets, dispatch after owner sees the device build.

## PREVIOUS 2026-07-12 ~00:00 (punch list CLEARED except direct-open lane; PRs 89–93 merged)

**Live state:** daemon running lane-Q-era binary == master content (list enrichment + approval
prune live; backup at `~/.lancer/bin/lancerd.bak-pre-p93`). **Owner phone is ORPHANED** — sim
holds the relay slot (code 892188); owner backup at `~/.lancer/relay-pairing.json.owner-backup-2237`
(code 208937 — stable identity means phone auto-reconnects when that file is restored, no code
entry). RESTORE after the final sim gate + tell owner. `~/.cursor/mcp.json` restored ✓.

**Merged tonight (all sim-live-loop-gated, evidence in docs/test-runs/2026-07-11-sim-live-loop-gate/):**
- **#89** repo-match grouping/dedup — PASS (trailing-slash dedup, thread grouped, live pong round-trip).
- **#90** Proof Reel + receipt card — PASS after the gate caught a real ship-blocker: required
  `conversationId` vs daemon `omitempty` → every real receipt failed decode (fixed `28fb0a7c`,
  regression test on verbatim daemon payload). Reel sheet proven with an approved `ls` run
  (approval card → Approve → receipt card → Stop 1/1 playback).
- **#91** Flight Recorder — PASS (timeline of real ledger events; stdout/receipt/exit; expand OK).
  Backlog nit: turn-row a11y label repeats 4×.
- **#92** startup prune of dead-run pending approvals (punch #5) — Fable full-diff reviewed
  (fail-closed: terminal/absent→drop, unknown/live/empty→keep); **live-proven** in daemon log:
  `restoreQueue: pruned 1 stale approval(s)`.
- **#93** honest thread-list status (punch #1) — daemon list carries lastTurnID/lastTurnStatus;
  merge advances running→terminal only; refresh syncs when a local turn is running + on
  scenePhase active. Gate caught a second bug: connection-state-read-once hydration race
  (fixed `7e03b466`). Proven end-to-end: Working badge → daemon restart mid-run → list shows
  Failed WITHOUT opening the thread.

**Punch list status:** #1 ✓ (#93) · #2 ✓ (6 live sends round-tripped tonight incl. approval
flow) · #3 ✓ (#89) · #4 IN FLIGHT — lane R `fix/p1-agents-direct-open` (Grok, dispatched):
row tap → arm observed continue → LiveThreadView adopt-without-initial-send; interstitial
deleted. Needs: my verify + app-target build + sim gate (Agents row tap) + merge. · #5 ✓ (#92)
· #6 ✓ (transcript responsive post-#87) · #7 APNs co-test still owner-gated.

**Then:** ONE device build to owner from master (after lane R) — review list: thread-list
badges clear on foreground; receipt card + Proof Reel on completed runs; Flight Recorder rows
in thread detail; Agents-row direct open. Then feature queue (plan-limits collector → account
switcher → in-app messaging).

**New gotchas (also appended to REVIEW_STANDARDS):** Go `omitempty` ↔ Swift required field =
prod-only decode failure — wire fixtures must include a verbatim daemon capture · never read
`firstConnectedMachine` once at call time (hydration race — wait like ShellLiveBridge) ·
sim typing: HID type_text doesn't land in this iOS 27 sim's fields — use `simctl pbcopy` +
long-press + `idb ui tap` on the Paste callout (SwiftUI buttons still need snapshot_ui refs;
UIKit callouts accept idb) · two command-center repo rows on Workspaces root (discovered-16 vs
added-1) — likely path-spelling split predating #89's normalizer on host-side cwds; backlog.

## PREVIOUS HANDOFF 2026-07-11 ~21:15 (superseded above; kept for context)

**Live state:** daemon deployed from master `d89a69e4`+#88 on owner code 208937, queue.json
clean (2 ghost approvals hand-purged; class fix pending), 0 running turns. Owner phone has
wave-4 build (master `027e6ef4`), pairing auto-restores (stable identity WORKS — proven ×6
tonight). Sim identity pinned to dead codes — clean-reinstall sim before any sim gate.

**CHAT RELIABILITY PUNCH LIST (owner: fix ALL today):**
1. **Thread LIST shows stale "Working"** for turns the daemon marked failed (screenshot
   21:10) — list statuses only refresh on thread open; need list-level refetch on
   foreground/poll (ConversationSyncCoordinator / thread list store). NOT yet fixed or laned.
2. Owner's send got 'machine didn't respond' twice tonight — (a) dispatch racing relay
   re-key second (backlog), (b) handlers now off-loop (#87 fixed the big one). Re-verify send
   works end-to-end on device after list fix.
3. Lane P `fix/p1-repo-match` — DONE, PR #89 open (tests green; needs sim gate before
   merge). ⚠️ worktree is NESTED at .worktrees/fix-router-async/.worktrees/fix-orphan-turns/
   .worktrees/p1-repo-match (cd bug); clean up all three nested worktrees after merging.
4. Tap agent session → open conversation DIRECTLY (kill "Continue in Lancer" screen) — owner
   explicitly annoyed. Not laned yet.
5. Stale-approval class fix: drop pending approvals whose run is dead (same startup
   reconciliation as #88 turns). Not laned yet.
6. Transcript view slowness re-check post-#87.
7. APNs lock-screen co-test NEVER RUN — owner was mid-session; ask for "closed" signal, fire
   gated action, trace daemon→conduit-push logs (`gcloud logging read` project
   roshan-agent-f1c2466d service conduit-push).

**Landed tonight:** #80 keepalive · #81 stable identity · #82 model-argv · #83 git-wedge ·
#84 picker/haiku · #85 markdown+pacer · #86 Agents section · #87 handlers off messageLoop ·
#88 orphan-turn reconciliation. Sim-gate evidence: docs/test-runs/2026-07-11-sim-live-loop-gate/.

**Open PRs awaiting sim gate (all tests green, ui risk):** #89 repo-match · #90 proof reel ·
#91 flight recorder. Gate each with a real haiku run (receipt needed for #90), merge, then
ONE device build to owner. s27-deep-integration branch: S27-0 committed; NEXT S27-2a
Live-Activity restore. Cleanup: remove merged worktrees fix-router-async + fix-orphan-turns
+ nested p1-repo-match (3-deep nesting bug), fix-git-timeout, fix-model-argv, p2-* after
merge. Background procs: all stopped (test daemon /tmp/lth killed; monitors expired).

**Operational gotchas:** cursor headless dies on big ~/.cursor/mcp.json → `mv` to
.headless-hold during dispatch, ALWAYS restore · daemon redeploy = stop→mv→bootstrap, NEVER
cp; restarts kill in-flight runs (now reconciled honestly, still avoid during owner runs) ·
single relay slot: sim gates borrow via backup/restore of ~/.lancer/relay-pairing.json
(phone auto-reconnects) · `lancerd pair` codes expire ~15min unconfirmed · TCC: owner may
grant lancerd Full Disk Access; codesign lancerd queued for launch prep.

**Feature queue (after punch list):** plan-limits collector (lfg study:
docs/product/2026-07-11-lfg-study-and-usage-limits.md, MIT) → account switcher/hotswap →
in-app messaging + bug reports (needs owner scope confirm) → S27 lane → cross-device proof.

**Updated:** 2026-07-11 PM (update after every merge or blocker; this file is compaction insurance)
**Phase:** 1 — dogfood MVP. Phase 0 CLOSED: PR #69 merged (`fd7b56d5`); stashes + checkpoint/backup refs dropped; w0a branch deleted.

## FRONTEND REVERSAL (owner, 2026-07-11 PM) — read before touching UI

Owner supplied the Cursor Design reference set → the frontend is the **Codex Workspaces
shell** (`b472ffd3` line), NOT W0.A. PR #75 restores it. W0.A retired; PRs #72/73/74 closed
as superseded. Re-queue lanes against the restored shell:
- Tool-call cards re-port (pairing/presentation logic from closed #72 is shell-agnostic)
- Siri warning cleanup (redo of #73)
- LancerUITests rewrite (current suite targets the retired W0.A shell; kept only so
  xcodegen resolves)
- Known fidelity gaps from the Codex session: light-mode header-chip chrome subtler than
  reference; avatar orb oversized. Device dogfood items M2/M3/M4 unproven live.
- **Failure lesson (recorded):** the 07-10 purge docs said "W0.A KEPT / wipe abandoned" —
  the docs were wrong about which shell the owner meant. When a directive names a branch,
  attach a screenshot of what it looks like before acting on delete/keep decisions.

## Wave 3+4 COMPLETE on master (2026-07-11 ~20:00): #82–#86 · device build ready, phone offline

#86 Agents section merged (observed sessions list/transcript/continue; gate screenshot shows
3 REAL sessions incl. the orchestrator itself). Final device build from `027e6ef4` SUCCEEDED;
**install monitor armed — phone `unavailable`, installs+launches automatically on reconnect,
then ping owner.** Owner review list: Model chip (Haiku default) · markdown on algebra prompt
· streaming fluidity · Agents section listing Mac sessions. All lane worktrees cleaned.

## Dogfood wave 3 MERGED (2026-07-11 ~19:30): PRs #82–#85 — awaiting phone reconnect to install

#82 model-argv (latent: ANY explicit-model dispatch instant-exited — picker exposed it) ·
#83 relay-wedge (hung git on messageLoop; goroutine dump preserved; 10s CommandContext +
async receipt snapshot) · #84 model picker Haiku default + cloud chip removed · #85 markdown
HTML-conversion/block-boundaries + streaming pacer. Sim gate evidence:
docs/test-runs/2026-07-11-sim-live-loop-gate/ (both addenda). Daemon deployed at 36dc6ac9-era
tip on owner code 208937. **Device build SUCCEEDED but phone went unavailable at install time
— install + launch it the moment the phone reconnects, then ping owner (review moment:
Model chip → Haiku, algebra prompt markdown, streaming fluidity).**
Backlog logged: dispatch-vs-repair race orphaning a running turn; pairing-sheet expiry UX.
Feature queue: plan-limits collector (lfg MIT, docs/product/2026-07-11-lfg-study-and-usage-limits.md)
· account switcher/hotswap (Orca) · in-app agent messaging + bug reports (needs owner spec
confirm) · S27 lane (S27-0 done on branch) · cross-device continuation proof.

## Pairing friction SOLVED (2026-07-11 night): PRs #80 + #81 merged, prod-relay-proven

Root causes (backend-log-verified): (a) daemon sat on relay-reaped sockets forever (no read
deadline; x/net/websocket has no control-frame ping) — #80 adds 90s read deadline + bounded
expired-code giveUp; daemon REDEPLOYED. (b) E2ERelayClient minted a new keypair per instance
→ backend key-pin rejected every retry/reinstall as hijack — #81 adds Keychain-persisted
stable device identity (dev.lancer.relay, AfterFirstUnlockThisDeviceOnly, survives reinstall)
+ launch auto-restore + fail-closed corruption wipe. Sim gate vs PROD relay: pair PASS,
relaunch-no-code auto-reconnect PASS ("phone connected (paired)"). Owner pairs ONCE more
(final code 853535), then never again. Ops note: `lancerd pair` codes expire unconfirmed
~15min — generate immediately before pairing.

## S27 lane (owner top priority): iOS 27 SDK ALREADY INSTALLED — all packages CAN START NOW

Branch feat/s27-deep-integration: plan committed (docs/plans/2026-07-11-s27-deep-integration-Plan.md),
S27-0 target raise DONE on branch (cb7f3196, swift+app-target gates green). Next: S27-2a
Live-Activity widget restore (deleted in wipe — prereq for the Siri-dispatch headline),
S27-1 tests, S27-2 LongRunningIntent (sensitive), S27-3 Spotlight, S27-4 FM copilot
(iOS26+, parallel-safe), S27-5 verify-then-build. Queued: cross-device continuation proof.

## Dogfood round 2: PR #79 MERGED (2026-07-11 late) — streaming/timeout/transcript

Owner findings → fixes, all sim-gate-proven (evidence `docs/test-runs/2026-07-11-sim-live-loop-gate/`):
streaming mid-run PASS · false 90s timeout removed (LivePollPolicy) · follow-up round-trip
PASS · full-transcript bug (follow-ups wiped prior turns) found BY the new gate, fixed.
New build installed+launched on phone from `e7619069`; owner re-pairs with code 221157.
**Open:** artifacts surface lane (LiveThreadView freed up) · streamed-markdown newline
cosmetic · **notifications = device-only, owner co-test pending (APNs diagnosis prepped
next)** · SiriRelevanceCoordinator warnings redo.

## Dogfood round 1: ALL THREE FINDINGS FIXED AND MERGED (2026-07-11 night)

PR #76 (composer onSend required, repo-scoped send) · #77 (chat/PR polish to reference) ·
#78 (real data everywhere; +app-target access-level hotfix 65ba058c — swift build on macOS
missed an iOS-gated public-init/internal-type error, CI build_sim caught it). Dogfood
candidate installed+launched on phone from master 36d81be6. ~/.cursor/mcp.json RESTORED.
Reinstall wipes pairing — owner must re-pair (`lancerd pair` for a fresh code).

## Dogfood round 1 (owner, 2026-07-11 evening) — pairing WORKED; 3 findings → lanes

1. **P0 composer bug** (root-caused by Fable): `NewChatComposerView.send()` = `onSend?();dismiss()`;
   ThreadListView:86 + ThreadDetailView:83 pass NO onSend → silent dismiss. Lane F
   (`fix/p1-composer-onsend`, Grok) makes onSend required + repo-scoped cwd.
2. **Chat UI "looks horrible"** → Lane H (`feat/p1-chat-polish`, Grok): LiveThreadView/
   ThreadDetail/PRDetail to cursor-reference quality, native AttributedString markdown.
3. **Mock data everywhere** → Lane G spec ready (scratchpad/laneG-SPEC.md): real repos from
   chatRepo + AddRepo persistence, real threads, honest empty states, kill placeholderCwd.
   Dispatch AFTER F merges (shared files: WorkspacesView, ThreadList, Composer).

**Cursor CLI MCP-limit gotcha (recurring):** headless `agent -p` dies with "Too many MCP tools"
since ~/.cursor/mcp.json grew. Project-level empty .cursor/mcp.json does NOT override. Current
workaround: `mv ~/.cursor/mcp.json ~/.cursor/mcp.json.headless-hold` during dispatches —
**RESTORE IT after lanes finish** (owner's IDE loses MCP servers while held).

## Phase 1 lanes (dispatched 2026-07-11, Grok 4.5 xhigh via cursor-agent)

| Lane | Branch / worktree | Scope | Write-set | Status |
|---|---|---|---|---|
| A | **PR #72 open — OWNER GATE (ui)** | Tool-call cards + indicator enum; rebased on master; swift gates green, 22 new tests; Orca attribution present | CursorStyle + tests | awaiting owner batched eyeball |
| C | `feat/p1-question-card` (stacked on A) / `.worktrees/p1-question-card` | Question card on W0.A shell + RelayQuestionIngest reconcile w/ 30a28e26 | Bridge/RelayQuestionIngest, CursorShellLiveBridge, CursorWorkThreadView, new CursorQuestionCard | dispatched (Grok) |
| E | `chore/p1-siri-warnings` / `.worktrees/p1-siri-warnings` | 25-warning mechanical cleanup | Lancer/SiriRelevanceCoordinator.swift | dispatched (Composer) |
| B | **MERGED** PR #70 (`eeaa6134`) | 81-case permission matrix + **real fail-open bug found & fixed**: `policy/match.go` corrupt ExpiresAt (effect-aware fail-closed after Opus CI correction) | — | done; worktree removed |
| D | **MERGED** PR #71 (`57bf761d`) | Ordering already existed (C1–C2); +8 ordering tests, force-unwrap removed | — | done; worktree removed |
| C (queued) | — | Re-port master-line M1 question card onto W0.A shell (from #69 integration) | CursorWorkThreadView + new card file | blocked by A (same write-set) |
| queued | — | Stop ladder + derived-offline (§1.1 step 5) | chat internals | after A |
| queued | — | Unread read-cursor (§1.3) | thread view + list | after A+D |
| queued | — | SiriRelevanceCoordinator warning cleanup (25 warnings) | Lancer/SiriRelevanceCoordinator.swift | Composer, anytime |

**Integration decision #69 (see STATUS_LEDGER):** W0.A owns the iOS UI; master's parallel
Workspaces-shell line dropped from tree (git history keeps it); master backend kept incl.
questions M3 daemon + relay wire fixes; dispatch-cwd fix re-applied.

**Tier 0 re-proof prep:** daemon redeployed from tip (running); signed device build SUCCEEDED;
checklist `docs/test-runs/2026-07-11-tier0-owner-checklist.md`; **blocked: phone 557A7877
unavailable — owner must connect it, then install + ping.**

**CI reviewer:** cursor-agent headless, `claude-opus-4-8-thinking-high`, prompt via stdin
(first run failed on MAX_ARG_STRLEN, fixed `a8101d9c`). After first successful run, verify
Cursor dashboard shows plan usage, not metered — if metered, STOP CI reviews and tell owner.
**Roadmap SSOT:** `docs/product/2026-07-10-lancer-agent-build-roadmap.md` · direction:
`docs/product/2026-07-10-lancer-daily-driver-definition.md`

## Model slugs (verified via `agent models`, 2026-07-11)

| Role | Slug |
|---|---|
| Default implementer | `grok-4.5-xhigh` (Cursor Grok 4.5; `grok-4.5-fast-xhigh` when speed matters) |
| Mechanical edits / first-pass review summaries | `composer-2.5` |
| Fallback + sensitive + repo-skill work | Claude `sonnet` high via Agent tool |
| CI stage-4 reviewer | `claude-opus-4-8-thinking-high` via cursor-agent headless (`CURSOR_API_KEY` repo secret; NOT Grok, cross-model independence) |
| Cursor auth | logged in (sidewhinder2k3@gmail.com); `gh` auth OK (RoshanDewmina, repo=conduit) |

**Standing constraint (owner, 2026-07-11): subscription-only billing.** No pay-per-use API
keys anywhere in the pipeline; all model calls ride Cursor Ultra or the Claude subscription.
Metered-only tool → propose subscription-backed alternative + ask owner. After the first CI
review run, verify the owner's Cursor dashboard shows it as plan usage, not metered — if
metered, STOP CI reviews and tell the owner.

## Phase 0 log (2026-07-11)

| Item | Status | Evidence |
|---|---|---|
| **Empty-tree tip repaired** | DONE | `1c102940` had tree `4b825dc6…` (the empty tree — wiped index at commit time). Backup ref `backup/w0a-empty-tree-tip`; `git reset --mixed bd4bcef8`; recommitted as `4c350a52` (869 files in tree) |
| Dispatch cwd fix landed | DONE | `4c2634df` fix(daemon): fail-fast missing/non-dir cwd (`resolveDispatchCWD`); `go test ./...` ok (lancerd 44s + policy); Fable full-diff review passed (sensitive path) |
| Scorched-wipe worktree removed | DONE | worktree was clean, on master; branch `feat/frontend-scorched-wipe` tip `80407933` verified ancestor of master → `-D` deleted. Frontend KEPT = W0.A CursorStyle shell (present on this branch) |
| build_sim green | DONE | XcodeBuildMCP build_sim SUCCEEDED 29.8s on `feat/chat-overhaul-w0a` (post-repair). Warnings only: `Lancer/SiriRelevanceCoordinator.swift` unused `try?` / var-never-mutated ×25 — queued as Composer cleanup |
| REVIEW_STANDARDS.md | DONE | created, seeded from ENGINEERING_PROCESS review bar + verdict JSON contract |
| claude-code-action workflow | DONE (blocked on secret) | `.github/workflows/claude-review.yml`; **owner must `gh secret set ANTHROPIC_API_KEY -R RoshanDewmina/conduit`** — repo has no secrets |

## Branch / worktree state

- `feat/chat-overhaul-w0a` — active, tree clean (only untracked: owner's personal
  `visual-first-communication.md`, left alone). Ahead of origin; push pending.
- Stashes kept until W0.A merges: `stash@{0}` (W0.A 19-file checkpoint), `stash@{1}` (pairing
  fixes) — content believed landed in branch commits; verify before dropping.
  `checkpoint/w0a-dogfood-pre-scorched-wipe` + `backup/w0a-empty-tree-tip` refs kept.
- Stale worktrees under `.worktrees/` (a3-r*, chat-*, w0-*, push-gaps, fix-daemon-flake) —
  audit each for unmerged work before removal; NOT part of Phase 0 scope.
- `claude/amazing-mayer-246fef`: cherry-pick only, never wholesale-merge.

## Owner-gated queue

1. Merge `feat/chat-overhaul-w0a` → master (ui risk + daily-loop change ⇒ owner gate).
2. Tier 0 / 5c device re-proof on current tip (physical phone).
3. `gh secret set ANTHROPIC_API_KEY` for the PR reviewer workflow.
4. Start `docs/dogfood-log.md` (one line/day).

## Decisions log

- 2026-07-11: dispatch.go dirty change was pre-existing dogfood-fix work found in tree during
  repair; landed as its own commit after Fable full-diff review + go gate (no argv/vendor
  changes, cwd validation only — vendor-cli-adapter-audit concerns not implicated).
- 2026-07-11: stashes NOT popped — branch commits supersede; keep as safety until merge.

## Phase 1 lanes (next — spec before dispatch)

Six pieces per roadmap §1: pairing/trusted machines · thread list · chat thread finesse ·
composer · push approvals incl. lock screen · emergency stop. Disjoint write-sets; shared
files (Package.swift, project.yml) land first as tiny solo commits.
