# Frontend rebuild — Sim / Device Hub dogfood Plan

**Goal:** Prove as much of M2–M4 (pair → send → reply → in-thread Approve/Deny) as possible on **Simulator + Device Hub / `devicectl` / XcodeBuildMCP** before asking the owner for any physical-phone time.

**Branch / worktree:** `feat/frontend-rebuild-m1` @ tip in  
`/Users/roshansilva/Documents/command-center/.worktrees/frontend-scorched-wipe`  
**Code tip (verified 2026-07-10):** `2a71fa57` (M1–M4 committed, tree clean). Re-check `git log -1` before starting.

**Related:** `docs/plans/2026-07-10-frontend-rebuild-Plan.md` · Status · `docs/LIVE_LOOP_RUNBOOK.md` · `docs/wwdc26-lancer-opportunity-audit/05-device-hub-testing-plan.md` · `docs/product/OWNER_RELAY_TEST_GUIDE.md`

---

## Apple / platform facts (do not invent)

From Apple’s current “Running your app on simulated or physical devices” doc and Device Hub notes:

- Simulators run **inside Device Hub on the Mac**; they do **not** replicate physical-device performance or all hardware features. Features that need real hardware must be tested on a device.
- Automation under Device Hub is **`devicectl` / CoreDevice** (see local `devicectl help` — do not invent flags). Verified forms live in `05-device-hub-testing-plan.md`.
- **APNs:** Simulator can receive **local** pushes (`xcrun simctl push` / drag `.apns`). Real provider→APNs→token registration still needs a physical device (or APNs Sandbox remote push to sim on Apple silicon — still not a substitute for owner closed-app phone proof).
- This machine’s **iOS 27 Simulator HID/accessibility is unreliable** for taps (documented in `docs/test-runs/2026-07-02-device-hub-matrix-simulator-pass.md`). Prefer: DEBUG `LANCER_DESTINATION=…` launch seams, XcodeBuildMCP `snapshot_ui` / screenshots, typed env launches, and **protocol-level** proofs over raw `ui_tap`.

---

## What this session must prove (agent-owned)

| ID | Claim | How to prove without owner phone | Owner needed? |
|---|---|---|---|
| D0 | App builds + launches on iPhone 17 Pro sim | XcodeBuildMCP `build_run_sim` | No |
| D1 | Settings / Trusted Machines UI reachable | `LANCER_DESTINATION=trustedMachines` + screenshot | No |
| D2 | Live thread UI reachable (empty/no-host path) | `LANCER_DESTINATION=liveThread` + screenshot; confirm no crash with `RelayApprovalIngest` env | No |
| D3 | Mac `lancerd` + relay path up | Rebuild/install daemon; health checks; logs | Only if secrets/URLs missing — ask once |
| D4 | Sim can **pair** to a real host via relay | Drive pairing UI or documented pair flow; machine appears Connected in Trusted Machines | Prefer agent; **pause** only if QR/PIN requires human eyes |
| D5 | Send prompt → host reply on sim | Composer/live thread send; poll path hits host (`refreshConversation`); reply visible | No if D4 green |
| D6 | Pending approval appears in-thread | Trigger gated tool on host; card shows via `RelayApprovalIngest` | No if D4–D5 green |
| D7 | Approve / Deny completes | Tap Approve (or call ingest API from a DEBUG seam if HID fails); daemon unblocks; audit/log evidence | Prefer agent; owner only if HID blocked |
| D8 | Failure paths | No machine → send fails visibly; remove machine → gone | No |

**Explicitly deferred to owner (do not fake PASS):**

- Physical iPhone install / re-pair (ask before any reinstall — wipes pairing)
- Real APNs while app force-quit / lock screen
- Anything that only fails on device thermal/network

---

## Milestones (one verify bar each)

### S0 — Prep + inventory
- Confirm branch tip, clean tree (or list dirty files; don’t revert unrelated).
- Confirm XcodeBuildMCP defaults → this worktree `Lancer.xcodeproj` / scheme `Lancer` / iPhone 17 Pro / `dev.lancer.mobile`.
- List available `LANCER_DESTINATION` cases from `WorkspacesView.swift`.
- Re-verify `devicectl help` for install/launch/screenshot/env forms.
**Verify:** paste `git log -1`, defaults JSON, destination enum list.

### S1 — Cold UI smoke (no daemon)
- `build_run_sim`
- Launch with `LANCER_DESTINATION=trustedMachines` → screenshot
- Launch with `LANCER_DESTINATION=liveThread` → screenshot (expect no-host / empty failure, not crash)
**Verify:** screenshots under `docs/test-runs/2026-07-10-frontend-rebuild-sim-dogfood/` + build log.

### S2 — Host stack up
- `cd daemon/lancerd && go build -o lancerd . && go test ./...` (from worktree or main — same module)
- Ensure resident daemon / relay reachable per `LIVE_LOOP_RUNBOOK` Phase for **relay** (V1). Prefer existing local/staging relay; do not invent new cloud infra.
- Document exact commands + health evidence in the test-run doc.
**Verify:** `go test` PASS + daemon/relay health evidence. **STOP and ask owner** only if a secret/URL is missing.

### S3 — Pair on Simulator (M2)
- Pair sim ↔ host through Trusted Machines / pairing sheet.
- If HID taps fail: use whatever DEBUG/automation path already exists; if none, add a **minimal DEBUG-only** seam (e.g. paste-code field already focused + `type_text`, or a one-shot `LANCER_PAIR_CODE=…` **only if** a safe pattern already exists in repo — do not invent insecure production shortcuts).
- Prove: machine listed, Connected (or honest reconnecting), Remove works.
**Verify:** screenshots + log lines showing pair success. Mark FAIL honestly if blocked.

### S4 — Send + reply (M3)
- From Workspaces composer (or live thread), send a **low-risk** prompt to the paired host.
- Confirm `ShellLiveBridge.pollUntilTerminal` path refreshes from host (not local-only) — evidence: reply text appears **or** structured logs showing `refreshConversation` + terminal status.
**Verify:** screenshot of reply + timing notes. If times out, capture logs and stop (do not claim PASS).

### S5 — In-thread approval (M4)
- Trigger a policy-gated action on the host that creates a pending approval over relay.
- Confirm card appears on live thread (machine-scoped — documented limitation OK).
- Approve once; confirm daemon continues. Optionally Deny on a second gated action.
- If UI tap impossible: exercise `RelayApprovalIngest` decision path via the smallest DEBUG hook that still goes through `ApprovalRelay.enqueue` + `registerRelayOrigin` (must not bypass those).
**Verify:** screenshot of card + approve evidence (audit/daemon log).

### S6 — Write results + owner ask list
- Write `docs/test-runs/2026-07-10-frontend-rebuild-sim-dogfood/README.md` with PASS/FAIL/SKIP per D0–D8, commands, screenshot paths.
- Update `docs/plans/2026-07-10-frontend-rebuild-Status.md`.
- Flip Plan.md Progress checkboxes for M1–M4 if still unchecked (doc drift fix).
- End with a **short owner-only checklist** (≤5 bullets) for physical device — only items that actually failed or are APNs/device-only.

**Verify:** results doc exists; Status updated; STOP.

---

## Global constraints

- Do **not** reinstall / erase the owner’s physical phone without explicit ask.
- Do **not** merge to `master` / push unless owner asks.
- Do **not** touch `daemon/**` except rebuild/test/run as needed for dogfood (no feature edits unless a blocker bug is found — then fix minimally + note in results).
- Prefer evidence over narrative. “Should work” is FAIL.
- One milestone → evidence → next. Max 2 fix attempts per failed step, then document and continue or STOP for owner.
- Token-efficient: don’t re-derive M1–M4 design; code is already on the branch.

## Out of scope

- New product features / Question cards / markdown polish
- Full Device Hub accessibility matrix (that’s a separate pass)
- Watch
- Declaring Tier-0 closed-app APNs PASS from simulator alone

## Progress

- [ ] S0 Prep
- [ ] S1 Cold UI smoke
- [ ] S2 Host stack
- [ ] S3 Pair on sim
- [ ] S4 Send + reply
- [ ] S5 In-thread approval
- [ ] S6 Results + owner ask list

## Decision log

- 2026-07-10: Owner asked for sim/Device Hub–first dogfood to minimize their time; physical phone only after agent exhausts sim-provable path.
- 2026-07-10: Apple Device Hub = simulators on Mac; physical still required for true hardware/APNs closed-app proof.
