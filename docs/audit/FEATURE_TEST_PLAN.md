# Lancer — Feature Test Plan

Goal: prove Lancer is solid enough to **develop Lancer from the phone** — run
Claude Code / Codex / OpenCode sessions, review/approve, and steer next steps
without touching the Mac. We go **phase by phase**: each phase has a goal, exact
steps, a pass bar, and an honest note on what can only be proven on a **physical
device** vs the simulator.

Legend: ✅ verified this session · ⏳ to test together · 📱 device-only truth · 🧪 sim-OK

---

## How sessions actually get created (so the tests make sense)

There are **two** ways an agent runs — both relevant:

1. **Interactive session (block terminal).** Fleet → connect a host → a live SSH
   PTY opens as a full-screen `SessionView`. You type in the command bar and
   launch the agent yourself (`claude`, `codex`, `opencode`). Output renders as
   Warp-style blocks. The **resident `lancerd`** on the host brokers approvals
   via the agent's hooks → risky action pauses → card on your phone → approve →
   run resumes. *This is where you "enter prompts and discuss next steps."*

2. **Dispatch (headless task).** Fleet → `+ task` → `DispatchView` → `agent.dispatch`
   RPC. Here **lancerd launches the process itself**: `claude -p <prompt>` /
   `codex exec` / `opencode run`, applies `--model` if you pick one, enforces
   policy + daily budget, streams `agent.run.output`/`agent.run.status` back, and
   raises approval cards. No typing into a PTY — fire-and-monitor.

So: **lancerd owns the dispatch path end-to-end; the interactive path is the SSH
PTY + lancerd-brokered approvals.** Phase 1 tests both.

---

## Phase 0 — Environment & clean slate  ✅ (done this session)

- ✅ Demo seed is now **opt-in** (`LANCER_SEED_DEMO=1`); a normal launch is a
  true clean slate (boots to onboarding, empty Fleet, $0.00, "Connect a host").
- ✅ DEBUG **Settings → DEVELOPER → "Reset local data"** wipes hosts/snippets/
  approvals on demand (confirmation dialog).
- ✅ Footer tab bar clearance raised (12→26pt) so taps don't hit the home pill.
- ✅ App-target build SUCCEEDED, 0 warnings / 0 errors.
- ⏳ **Decision:** test on simulator or physical device? And which SSH host?

---

## Phase 1 — Connect + create a session  (CORE)

Goal: connect to a real host and start an agent **both** ways.

Steps:
1. Onboarding → "i already use lancer" (or "get started") → **add host** (SSH
   command or fields). Save. 🧪
2. Tap the host → connect. Expect: TOFU host-key prompt (first time), then live
   `SessionView`. 🧪 (TOFU prompt must appear — production safety invariant.)
3. **Interactive:** in the command bar type `claude` (or `codex`/`opencode`),
   send. Expect: a block forms, the agent boots inside its block. 📱 (live text
   entry into the PTY is the one thing the simulator can't prove — needs a real
   keyboard.)
4. **Dispatch:** back to Fleet → `+ task` → pick agent + model + prompt →
   Dispatch. Expect: feedback alert with a runId; output streams; status goes
   running → exited. ⏳

Pass bar: a host connects with TOFU, an interactive agent launches in a block,
and a dispatched task returns a runId + streams output.

**Session results (2026-06-15, simulator + live VPS `hermes-box`):**
- ✅ **Connected live, interactive path.** SSH **ed25519 key auth** succeeded to
  `silvapulle@100.83.108.60`; real shell prompt `silvapulle@hermes-box:~$` renders
  in Warp-style blocks; first block completed `✓ exit 0` in 0.84s; "Streaming"
  badge + key panel (Esc/Tab/Ctrl/Tmux/arrows) present. 🧪
- ✅ **TOFU verified.** Prompt fired on first connect; displayed fingerprint
  `SHA256:Xy3CxwoYEY01CqkLAlANuS1DET6YBFpGp41Zfwu…` **matched** the VPS's real
  ED25519 host key (`…Zfwuh6+E`). No bypass. Production invariant holds. 🧪
- 📱 **Typing not provable on sim.** `ui_type "ls -la"` did not reach the command
  pill (keyboard up, but text never registered) — the documented automation
  limitation. Needs a real device. No bytes sent to the VPS.
- ⚠️ **lancerd is NOT installed/running on the VPS** (`pgrep lancerd` → none).
  The raw SSH PTY works without it, but **approval brokering (Phase 3) cannot work
  until lancerd is installed on the host.** Blocks Phase 3 on this VPS.
- Confirms **Finding #5**: connect lands directly in the full-screen block
  terminal, not a monitoring overview.
- ✅ **lancerd installed on the VPS + bridge attached (verified).** Cross-built
  `lancerd` for linux/arm64, deployed to `~/.lancer/bin/lancerd`, ran
  `lancerd install` (wrote systemd user unit + **auto-wired the Claude PreToolUse
  hook**), started the resident daemon (`systemctl --user enable --now
  lancerd.service` → active, listening on `~/.lancer/lancerd.sock`). `doctor`:
  9 ok / 2 warn (no custom policy = default-ask; that's desired) / 0 fail. App
  reconnected → status bar shows **"bridge connected"**, and the VPS shows BOTH
  `lancerd daemon` and `lancerd serve` (the app's attached bridge channel)
  running. Full chain live: app ↔ `lancerd serve` ↔ resident daemon. Approval
  brokering (Phase 3) is now unblocked on this VPS.
  - ⚠ Not yet done: `loginctl enable-linger` (needs sudo) so the daemon survives
    after all SSH sessions close — defer / have the owner run it.

---

## Phase 2 — Live chat / prompts  (CORE)

Goal: hold a working conversation with Claude Code from the phone.

Steps:
1. In a live session, send a multi-line prompt ("read X, propose a change"). 📱
2. Confirm streamed assistant output renders in-block, scrolls, and is readable.
3. Send a follow-up ("now do Y") — confirm context continuity. 📱
4. Try an inline TUI agent (claude/codex) — confirm it renders inside its block,
   not as a broken full-screen swap.

Pass bar: round-trip prompts work, output is legible, follow-ups keep context.

---

## Phase 3 — Approvals: halt / pause / resume  (CORE)

Goal: the safety loop — agent pauses on risk, you decide on the phone.

Steps:
1. Have the agent attempt a risky action (e.g. `rm -rf`, force-push, file write
   under an "ask" policy). Expect: run **pauses**, approval card appears (Inbox +
   notification). ✅ (loop proven live earlier — approve→resume at +13s.)
2. **Approve** → run resumes; audit logs "approve".
3. Repeat, **Deny** → run does not proceed; audit logs "deny".
4. **Halt/stop** a running session (disconnect / stop control); confirm it ends
   cleanly and can be reconnected. ⏳
5. Pause/resume a dispatched run (stop/pause/resume RPCs exist). ⏳

Pass bar: approve resumes, deny blocks, both audited; halt + reconnect work.

**Session results (2026-06-15, live VPS, bridge connected):**
- ✅ **Approve→resume proven end-to-end.** Triggered `claude -p` on the VPS with a
  Bash call (`ls -la ~`). PreToolUse hook → `lancerd agent-hook` → resident daemon
  → app raised a real card: "Claude Code is asking permission to run Bash · HIGH",
  cwd `/home/silvapulle`, blast-radius panel. Tapped **Approve** → claude resumed,
  ran the command, returned the listing, exited 0. Inbox card moved pending→
  **"DECIDED · approved"**.
- ✅ **Tamper-evident audit chain.** `~/.lancer/audit.log`: `escalate`(ask,
  rule `ask-high`) then `approve`, same `approvalId`, hash-chained via `prevHash`.
- ⏳ Deny path, halt/disconnect, dispatch pause/resume: not yet (deny is the same
  path inverted; worth a quick confirm on device).
- 📌 **Read-only tools auto-approve by design** (`lancer-hook.sh` exits 0 for
  Read/LS/Grep/WebFetch/…), so only Bash/Write/Edit/Patch raise cards.

---

## Phase 4 — File viewing & diff  (CORE)

Goal: review what the agent changed.

Steps:
1. Open `FilesView` (SFTP browse) on the connected host → open a file →
   `FilePreviewView` renders with syntax/text. ⏳
2. Trigger / open a patch → `DiffView` renders unified diff (+/− lines, file
   headers). ⏳
3. From a patch-type approval, confirm the diff sheet opens directly. ⏳

Pass bar: can browse to a file, read it, and read a diff. (Completeness of
syntax highlighting / large-file handling noted as findings, not blockers.)

---

## Phase 5 — Notifications  (CORE)

Steps:
1. Foreground: approval → in-app/local notification fires. 🧪
2. Backgrounded app: approval → banner on lock screen, tap → opens the card. 📱
   (APNs to a backgrounded/closed app is **device-only** truth.)
3. Dynamic Island / Live Activity shows pending-approval count. 📱

Pass bar: you get notified within seconds while not looking at the app, and the
tap deep-links to the decision.

---

## Phase 6 — Multiple sessions at once

Steps:
1. Connect host A, start an agent; connect host B (or a 2nd slot), start another.
2. Fleet shows both slots with independent status/spend. ⏳
3. Switch between them; approvals route to the correct session. ⏳
4. One session's activity doesn't stall the other.

Pass bar: ≥2 concurrent sessions, independent state, approvals routed correctly.

---

## Phase 7 — Model selection

Steps:
1. Dispatch path: `+ task` → Model menu (Agent default / Opus / Sonnet / Haiku)
   → dispatched argv includes `--model`. ✅ (picker built; ⏳ confirm it reaches
   the process.)
2. Interactive path: launch `claude --model …` yourself in the PTY. 📱
3. Confirm wrong/unavailable model surfaces an error, not a silent no-op.

Pass bar: chosen model demonstrably drives the run.

---

## Phase 8 — Secondary features

- Snippets / command palette (create, run, ranking). ⏳
- SSH keys: create/import, biometric gate. ⏳ 📱 (Face ID is device-only.)
- Settings: policy editor, autonomy presets, audit log view, trust & privacy. ⏳
- Host health + Quota Guard live data (currently mock-verified). ⏳
- iCloud sync of hosts/snippets across devices. ⏳ 📱

---

## MAJOR — Target UI redesign is NOT implemented

The app is running the **old design everywhere**. A full **target-UI design board**
exists (React/JSX mockups served at `http://localhost:4178/index.html`, source in
`docs/audit/migration-board/`, exported PNGs `board-*.png` / `verify-*.png`) and
**none of it has shipped**. This is a parallel track to functional testing: as we
walk each screen we record **(a) does it function** and **(b) does it match the
target design** — and right now (b) is "no" on every screen.

Target screens observed on the board (all unimplemented):
- **Onboarding** — intro → **"Pair the bridge"** (`curl … | sh` + QR / pair-code,
  e.g. `4 8 2 9`) → **"How cautious?"** (Caution / Balanced / Bypass presets) →
  first-run demo inbox. (This pairing flow IS the fix for finding #1.)
- **Core loop** — redesigned **inbox/approval queue**, session approval cards with
  Deny / Approve / Approve+run, **Face-ID gate on critical actions**, edit-&-run.
- **Trust & vendors**, **Start & govern (settings)**, backend surfaces, pairing,
  trust screens.

Note: a prior "Overview Board migration phases 0–3 done" was recorded, but the
running app does **not** reflect this target board — treat the board as the
source of truth for the redesign and re-verify each screen against it.

**Plan addition:** stand up a per-screen migration checklist (old → target),
prioritize after the core loop is proven functional (Plan B). Wire QR pairing as
part of the onboarding redesign.

## Findings log

- **Finding #1 — SSH onboarding is wrong for a phone-first tool.** Authorizing a
  fresh key on a key-only server from a phone (no computer) is a dead end. SSH is
  only the *install-free* default; it should become the power-user fallback.
  **Fix (next session):** front the already-scaffolded pairing path —
  `daemon/lancerd/install.sh` (`curl | sh`) + `BridgePairingView` /
  `E2ERelayPairingView` / `E2ERelayClient` + `daemon/push-backend` relay — and
  **wire QR pairing** (today it's a typed `000000` placeholder) or design an even
  smoother handshake. Decision this session: **Plan B** — use SSH to punch
  through onboarding now so we can test the core loop; fix onboarding after.

- **Finding #2 — the "Pair the bridge" flow is a mockup of non-functional infra.**
  - `curl -fsSL conduit.dev/install | sh` (BridgePairingView) — **`conduit.dev` doesn't
    resolve**; no release pipeline builds/publishes lancerd; repo `install.sh` is
    local-only. → Task #5.
  - Pairing relay is **built + tested** (push-backend `websocket_relay.go`, lancerd
    `e2e_router.go`, app `E2ERelayClient`, Fly config) but **`relay.conduit.dev` is
    not deployed**. → Task #6.
  - "paired" status copy is misleading; too much top text; needs polish → Claude
    Design redesign. → Task #7.
  - Liked + keep: macOS/Linux/Windows switcher + copy-command affordance.

- **Finding #3 — onboarding fixes shipped this session (verified on sim).**
  - Removed the "no server? we'll spin one up" managed-workspace page (advertised a
    feature not offered). Onboarding is now 3 steps; the caution-preset step's
    "continue" finishes → add-host. `ProvisioningWizard` code kept (unreferenced).
  - Final-step footer is now a full-width "continue" — fixes the inconsistent
    bottom-left step-dots + offset button. (Full footer/indicator consistency
    across the flow still belongs to the redesign, Task #7.)
  - **Resolved:** the AddHostView **"lancer cloud"** tab is now gated off behind
    `ProvisioningFeatureFlags.managedCloudEnabled` (default false; AddHostView reads
    the key directly). Add-host offers BYO-only. Verified on sim. Reversible — flip
    the flag when the hosted offering is real (Tasks #5/#6 territory).

- **Finding #4 — connect flow is far too heavy (signup-killer).** To use key auth
  you must dig into Settings → Security → SSH keys → generate, then come back and
  attach it. "No one would sign up if they have to do all that." Key gen/attach
  must be **inline in the connect flow** (generate + show pubkey + one-tap install
  on the host), not buried in Settings. Ties to the pairing redesign (Task #7).

- **Finding #5 — post-connect should be MONITORING, not the block terminal.**
  Today, connecting opens the SSH block terminal (`openSession` → full-screen
  `SessionView`). That defeats the product's first job — *monitoring* agent loops.
  Post-connect should land on the **monitoring/overview** (fleet, runs, approvals);
  the block terminal + dispatch are secondary, opened intentionally. (Aligns with
  the "control plane for agent loops, not a terminal" positioning.)

- **Finding #7 — "mock data won't reset" was the built-in first-run teaser (FIXED).**
  The phantom `npm install && npm run build` / `~/projects/my-app` approval that
  survived every reset was **not DB data** — it's `InboxViewModel.demoApproval`, a
  hardcoded first-run teaser shown by `effectiveApprovals` whenever real approvals
  are empty and `inbox.demoDismissed` is false. Reset wiped the DB but never the
  flag, so it returned every clean slate. Two bugs fixed this session (build green):
  - `demoDismissed` was a UserDefaults-backed computed prop (not `@Observable`-tracked),
    so tapping Deny/Approve set the flag but the card didn't disappear until a view
    rebuild. Changed to a stored, tracked property with a `didSet` UserDefaults write.
  - `DebugSeeder.wipeLocalData` now also sets `inbox.demoDismissed = true`, so
    "Reset local data" yields a genuinely empty inbox. Fresh installs still get the
    teaser once. (Verified live: Deny → tab-switch → "No approvals waiting".)

- **Finding #6 — question the persistent top "glyph bar".** The always-on status
  strip at the very top (pixel-glyph avatar + `host · Failed · SSH · reconnect`,
  `PersistentStatusBar`) may not earn its space. Revisit whether the glyph art is
  needed there at all. (Design — note only.)

- **Finding #8 — add-host mangled the saved record (root cause of "won't connect").**
  The stored host had `hostname = "100.83.100.60.22"` — the **port was concatenated
  into the hostname** (`:22` → `.22`) **and** the IP was wrong (`100`≠`108`), while
  `port` was *also* `22`. Worse, `authMethodType` defaulted to **`password`** with no
  key attached, even though a key existed — so it could never authenticate against a
  key-only server. There is also **no edit-host UI** (tap = reconnect, long-press =
  remove only), so a typo is unrecoverable without delete+re-add. Fixes needed:
  (a) host-input parser must split host/port correctly and reject junk; (b) connect
  flow should default to / prompt for key auth and let you pick the key inline
  (ties to Finding #4); (c) add an **edit host** screen. *(Unblocked this session by
  patching the DB directly: hostname→`100.83.108.60`, auth→ed25519 + key tag.)*

- **Finding #9 — Fleet shows a false "bridge connected" state.** Before the fix, the
  Fleet sub-line showed a green "● bridge connected" while the top status bar showed
  "Failed" and the host IP was actually **unreachable** (verified `nc` → refused).
  Two connection-state sources disagree, and one reports connected optimistically
  when it is not. Reconcile to a single source of truth; never show "connected"
  until the bridge/SSH session is actually established.

- **Finding #10 — `lancerd install` drops the Claude hook script but never wires
  it into `settings.json`.** After install, `~/.claude/hooks/lancer-hook.sh` exists
  and `doctor` reports "✓ hooks: installed: claude" — but that check only verifies
  the *script file*, not that Claude is configured to call it. `settings.json` had
  no `hooks` block, so the interactive PreToolUse approval path would silently never
  fire on a real device. (Proven by temporarily adding the `hooks.PreToolUse` block
  by hand → the loop worked; then reverted.) Fixes: (a) `install` should merge the
  `PreToolUse` entry into `~/.claude/settings.json` (idempotently, preserving the
  user's keys); (b) `doctor` should check the *settings wiring*, not just the file;
  (c) **graceful no-phone behavior** — the hook must fast-auto-approve (not block
  120 s) when the resident daemon has no attached client, or wiring it permanently
  will stall the user's normal `claude` runs on the host. Confirm this before any
  auto-wiring ships. Note the host's claude runs `bypassPermissions` mode, which
  makes the hook the *only* gate — all the more reason it must be wired + graceful.

- **Finding #11 — text entry is unusable under simulator automation.** Neither
  `idb ui_type` nor XcodeBuildMCP `type_text` (hardware-keyboard path) delivers
  characters to the app — affects the **dispatch form** and the **session command
  bar** alike (fields keep their placeholder; only a Paste/AutoFill callout shows).
  So on the simulator we cannot: type in the PTY, fill a dispatch, add/edit a host
  by typing, or fill any form. **A physical device is required** to test every
  text-entry flow. (The approval loop above was driven by launching claude on the
  VPS directly, which needs no app text entry.)

- **Finding #12 — connect is not beginner-friendly; key auth is buried + onboarding
  lacks it.** On a real device the saved host defaulted to **password** auth against
  a key-only server → endless failed password prompt with no useful feedback. The
  Ed25519 auth choice + key picker live under an "advanced" disclosure in
  `AddHostView`, and there is **no SSH-key setup in onboarding at all**. Fixes:
  default to / strongly surface key auth; bring key-gen + "authorize on host"
  (`ssh-copy-id` one-liner already exists in `AddHostView` V6) **into the onboarding
  flow**; when a password attempt fails against a key-only server, say so. Also: the
  whole SSH path requires the host to be network-reachable from the phone (public IP,
  same LAN, or Tailscale) — **the relay/QR pairing path (Finding #2 / Task #6) is the
  real fix** because both ends dial out, removing the Tailscale/same-network blocker.
  See `docs/audit/ONBOARDING_CONNECT_RESEARCH.md`.

## Known device-only gaps (carried from prior audit)

- Live **text entry** into a session/PTY (simulator suppresses the soft keyboard
  under automation — almost certainly fine, but only a device proves the +).
- **APNs** to a backgrounded/closed app.
- **Face ID / biometrics** for the app lock and SSH-key gate.

These are the reasons Phase 1–5 carry 📱 markers — we should run the truth-tests
on a real iPhone, using the simulator for everything it can legitimately cover.
