# Untested-feature live sweep — Phase 4 GAP LIST (merged to master; dogfood in progress)

**Date:** 2026-07-16  
**Tip:** `origin/master` @ `62b4424dc39df78d1a823bc33d7b597829ddc0e6` (`62b4424d`, PR #149)  
**Evidence root:** `docs/test-runs/2026-07-16-untested-feature-sweep/`  
**Session chain:** Claude `941bc90d` → Cursor C3/F-final → Claude Fable `3ddbf98e` (Wave 1) → Cursor `fb903282` (merge #140–#149 + phone dogfood) → session-hop sync `2758f384`.

---

## Owner digest (1 page)

### What this sweep proved

Live XCUITest + isolated-daemon lanes exercised 24 previously-untested surfaces against a tip that merges the night WP fixes with Orca terminal. Two **real P0 daemon bugs** were found, fixed, reviewed, and merged on this branch:

1. **F1 (`4e45dbaa`)** — first-send approval silently dropped when relay re-pair was mid-flight; `sendApproval` now bounded-retries.
2. **F4 (`1f08c3c6` / `ec425b40`)** — approve recorded but CLI never launched; resume path now launches on approve. **C3 live-proved** a real `claude` run + `474f104 sweep edit` commit after approve.

**Wave 1 + follow-ons on `origin/master` (VERIFIED via #140–#149):**

3. **FX7 (`a7749650` → merge `543566ba`)** — client treats sync `needsApproval` as awaiting-approval + polls same runID (unblocks #7 UI chain). **On master** via #140.
4. **FX5 (`a8a91761` → merge `2a872e1e`)** — pairing Connect pinned above number pad (#5). **On master** via #140.
5. **Lane P (`4382f1b8`+`7b4d4695` → merge `7707e4fa`)** — relay audit tail + coarse permission mode; YAML rules stay SSH-gated (#2/#3). **On master** via #140.
6. **FX10 (`5a3fce93`)** — background-tasks pill relay mirror. **On master** via #141; #10 **code FIXED**; live re-proof owed.
7. **#144** Policy stale SSH error — merged `ebc336f6`.
8. **#145** auth-preflight cold probe — merged `e7f06059`; phone `"Hi"` launch **PASS** (audit @ 21:20:25Z).
9. **#147** Proof under menu — merged `34d1f2de`; phone install claimed SUCCEEDED.
10. **#149** All Repos instant cache paint — merged `6b05372c`; tip `62b4424d`; phone install claimed SUCCEEDED.

### Top product gaps still open

| Pri | Gap | Verdict source |
|---|---|---|
| P0/P1 | **#7/#8/#9/#17/#23 live re-proof owed** — C4 harness never saw daemon `paired with phone`; FX7 path not observed (`awaitingCard=false`, `terminalRetry=true`). **Not disproven** — pairing gate failure, not product FAIL. | LC4 PARTIAL (harness) |
| P0 | **#2 Policy relay** — mode picker loads (**PARTIAL** live); stale SSH error **code-fixed** (#144 `ebc336f6`); phone UI re-proof owed | LC4 + #144 |
| P0 | **#3 Audit relay** — **PASS** live (`auditLoaded=true`, `auditSSHError=false`) | LC4 |
| P1 | **Background-tasks pill (#10)** — code-fixed on `origin/master` via FX10 (`5a3fce93`); C4 FAIL was pre-FX10 tip; **live re-proof still owed** on owner phone | LC4 + FX10 |
| P1 | **#5 Connect occlusion** — code FIXED (FX5); keypad screenshot proof still owed in C4 | code FIXED; visual C4 |
| P2 | Emergency Stop mechanically reachable but never cleanly PASS under harness timing | LA2 #1 BLOCKED |
| P2 | Mid-run feedback / tool-dedup / todo checklist still harness-BLOCKED | LD2 + LF-final #11/#14/#18 |

### What passed (live)

Onboarding gate · composer dispatch picker · inline approval card · pending-approvals banner · permission-mode pill · pairing timeout 30s · Agents tap→continuable Chat · thread-list filters/customize · thread-list metadata · PR detail honest-empty · repo name≠cwd plumbing · **F4 approve→launch (daemon)** · **Terminal open + real usage (F-final)**.

### C3 / F-final / Wave 1 status

C3 + F-final **completed** (`LC3-report.md`, `LF-final-report.md`). Wave 1 + FX10 + UX fixes **on `origin/master`** (#140–#149).
**Lane C4 partial** (`LC4-report.md`, `screenshots/LC4-*.png`) — pairing harness blocked #7 chain
(**still live-owed** — not product-disproven); Audit **PASS**; Policy **PARTIAL** (picker; #144 merged); FX5 **PASS**.
#10 **code FIXED** on master (FX10 `5a3fce93`); live re-proof owed. Owner phone: pair **confirmed**, launch smoke **PASS** post-#145; full 10-step checklist not fully evidenced.

---

## Ranked candidate scoreboard (canonical)

Best available verdict per candidate. Prefer A2/C2/D2/C3/F-final/LB over earlier lanes when both exist.

| # | Candidate | Best verdict | Lane | Notes |
|---|---|---|---|---|
| 1 | Emergency Stop | **BLOCKED** (harness) | LA2 | UI reachable; "No connected host" under re-pair race |
| 2 | Policy editor | **PASS** (phone) | Lane P + LC4 + WT | Picker loads on owner phone, no SSH flash (#144 holds); design concern WT-A2 |
| 3 | Audit feed | **PASS** (phone) | Lane P + LC4 + WT | Live on owner phone with same-night entries |
| 4 | Pending-approvals banner | **PASS** | LB | |
| 5 | First-run onboarding | **PASS** (+ Connect **PASS** live) | LB + FX5 + LC4 | `LC4-01-pairing-keypad.png` |
| 6 | Inline approval card | **PASS** | LB | Real git commit landed |
| 7 | Review pill → sheet | **FAIL** (live) | LC3 + LC4 | Pairing never settled; terminal Retry, no awaiting card |
| 8 | FileViewerView | **BLOCKED** → retest via C4 | LC3 | Was blocked on #7 UI |
| 9 | AddCommentSheet | **BLOCKED** → retest via C4 | LC3 | Was blocked on #7 UI |
| 10 | Background-tasks pill | **FAIL** (C4 pre-FX10) → **code FIXED** | LD2 + LF-final + LC4 | FX10 `5a3fce93` on master; live re-proof owed |
| 11 | Mid-run feedback queue | **BLOCKED** (harness) | LD2 + LF-final | followup send never enabled mid-run |
| 12 | Permission-mode pill | **PASS (rendering only)** — **WT-A: not wired** | LB + WT | Pill persists locally; never sent to daemon; `PresetDocument` dead code |
| 13 | Composer dispatch picker | **PASS** | LB | |
| 14 | Tool-call label dedup | **BLOCKED** (no chips) | LD2 + LF-final | bashCount=0 |
| 15 | Thread-list filters | **PASS** | LD2 | |
| 16 | Thread-list metadata | **PASS** | LD2 | |
| 17 | Receipt filesTouched | **BLOCKED** → retest via C4 | LC3 | Proof chip absent despite real edits |
| 18 | Todo checklist / activity | **BLOCKED** (harness) | LD2 + LF-final | Todo turn never gated/rendered |
| 19 | Repo name vs cwd | **PASS** | LC3 | Display `sc3-repo`; commit in absolute path |
| 20 | Pairing connect timeout 30s | **PASS** | LB | |
| 21 | Profile Usage placeholder gone | **PASS** | LA | |
| 22 | PRDetailView honest empty | **PASS** | LD | |
| 23 | Flight Recorder | **BLOCKED** → retest via C4 | LC3 | Was blocked on #7 UI |
| 24 | Agents tap-through | **PASS** | LA2 | Continuable Chat sheet |

**Terminal (Lane E / F-final):** open + real usage **PASS** (`LF-final-report.md`). Lifecycle partial; desktop-history unproven.

---

## Fixes landed this sweep (on `origin/master` @ `62b4424d`)

| Fix | Commit | Status |
|---|---|---|
| F1 approval delivery retry | `065481d9` → merge `4e45dbaa` | On master (#140); live-proven by C2/D2/C3 |
| F4 approve→launch resume | `ec425b40` → merge `1f08c3c6` | On master (#140); unit + **C3 live CLI + git commit** |
| Pairing timeout 8s→30s | `d1f8559a` | On master |
| F2 addrepo truncation | — | **Drop** (false bug narrative) |
| F3 pairing disagreement | doc branch `36310671` | No product fix; env artifact — confirmed by F-final terminal PASS |
| FX7 needsApproval → awaiting | `a7749650` → merge `543566ba` | On master (#140); **C4 #7 live owed** |
| FX5 Connect above keypad | `a8a91761` → merge `2a872e1e` | On master (#140); C4 screenshot PASS |
| Lane P policy/audit relay | `4382f1b8`+`7b4d4695` → merge `7707e4fa` | On master (#140); Audit PASS live |
| Drop sentry Package.resolved pin | `faeb80c9` | On master |
| FX10 background-tasks pill | `5a3fce93` | On master (#141); #10 code FIXED; live owed |
| Policy stale SSH error | `ebc336f6` (#144) | On master; phone UI re-proof owed |
| Auth-preflight cold probe | `e7f06059` (#145) | On master; launch smoke **PASS** |
| Proof under menu | `34d1f2de` (#147) | On master; UX **CLAIMED-UNVERIFIED** |
| All Repos cache paint | `6b05372c` (#149) | On master @ tip; UX **CLAIMED-UNVERIFIED** |

---

## Owner device walkthrough — 2026-07-16 evening (see `DOGFOOD_DEVICE_WALKTHROUGH.md`)

Live on the physical iPhone @ `62b4424d`: **approve loop PASS** (escalate→push-over-relay→approve→exit 0 in 21s), **Proof under ⋯ PASS** (#147), **Policy picker PASS** (#144), **Audit feed PASS on phone** (#3 upgrade from sim), **follow-up same-thread PASS** (same vendor session), **All Repos cold paint PASS** (#149). **FAILs/new gaps:** WT-A autonomy pill display-only (P1 — #12's PASS was rendering-only), WT-B live thread never renders completion (P1), WT-E no APNs approval push while locked (P1), WT-C return-visit spinner (P2), WT-D ⋯ missing on first entry (P2), WT-F `ls -la` risk-rated High (P3). E-Stop skipped (owner); #1 stays BLOCKED.

## Remaining work (ordered)

1. ~~**Merge-to-master + push**~~ — **DONE** (#140–#149 merged; tip `62b4424d`).
2. ~~**Owner phone dogfood**~~ — **DONE 2026-07-16 evening** (`DOGFOOD_DEVICE_WALKTHROUGH.md`); remaining from it: WT-A/WT-B/WT-E P1 fixes, E-Stop re-test, lock-push diagnosis.
3. **Lane C4 live sim re-test**: #7 chain (#8/#9/#17/#23) **still live-owed** — harness never got `paired with phone`; FX7 awaiting-card not observed. Also #10/#14 recheck + #1/#11/#18 harness retries.
4. **Publish / TestFlight** — not started (`docs/PUBLISH_READINESS_CHECKLIST.md`).

---

## Lane file index

| File | Role |
|---|---|
| `LA-report.md` / `LA2-report.md` | Governance — HID then XCUITest |
| `LB-report.md` | Onboarding / composer / approvals |
| `LC-report.md` / `LC2-report.md` / `LC3-report.md` | Review stack — F1 then F4 then post-F4 UI gap |
| `LD-report.md` / `LD2-report.md` | Chat pills / thread list |
| `LE-report.md` / `LF-final-report.md` | Terminal — FAIL under contention → PASS light load |
| `LC4-report.md` | C4 post-Wave-1 live re-test — PARTIAL (pairing harness blocked) |
| `GAP_LIST.md` | This synthesis |
| `screenshots/` | Per-lane PNG evidence |

**Incident:** accidental bare `lancerd pair` rotated `~/.lancer/relay-pairing.json` to fly.dev code `310440`; production daemon reconnected. Owner phone re-pair may be needed (L6 already owner-gated).

---

## 2026-07-17 evidence — WP5 re-proof (isolated sim + isolated daemon, master `f6c22629`)

Full method + logs: `docs/test-runs/2026-07-17-gap-reproof/evidence-log.md` +
`docs/test-runs/2026-07-17-gap-reproof/screenshots/`. Live sim (Simurgh `lease-205`) paired
over relay to a freshly built, fully isolated `lancerd` (`LANCER_STATE_DIR=/tmp/wp5-lancerd-state`,
own pairing code — production `~/.lancer` and the owner's phone slot were never touched;
`~/.lancer/audit.log` verified unchanged before/after).

| # | Candidate | 2026-07-17 verdict | Evidence |
|---|---|---|---|
| 7 | Review pill → sheet (needsApproval→awaiting, FX7) | **PASS** (live) | 3 real escalate→approve round-trips over relay (`bd7b6195…`/`8cbc210d…`/`57782942…`); real commit `b03e19b` landed in scratch repo; `c4-review-approval-card.png` |
| 10 | Background-tasks pill (FX10 relay artifact mirror) | **PASS** (live) | `gap10-background-tasks-pill.png` — 4 real task entries with live elapsed timers, populated via relay mirror; minor bug noted: stayed "Running" after the turn completed |
| 14 | Tool-call label dedup / chip rendering under real concurrent execution | **PASS** (live) | `gap14-tool-chips-expanded.png` — real (non-seeded) Claude Code run produced 4 distinct, correctly-labeled chips; no "Bash Bash:" dup-label bug |
| 1 | Emergency Stop | **FAIL** (new finding, supersedes prior BLOCKED) | Pairing was clean this run (no harness ambiguity). App reported "Stopped 2 runs" (`emergency-stop-result.png`) and daemon audit recorded `run-stopped` for both dispatch-level approvalIds, but the live host-side PreToolUse hook process gating the pending `sleep 120` escalation (pid confirmed via `ps`) stayed alive 6+ minutes after the stop, requiring manual `kill -9`. Root cause: `run-stopped` resolves the dispatch-level approvalId, not the specific in-flight tool-call escalation — the gate process is never signaled. |

**Net:** 3 of 4 re-proof items are now live-PASS on `origin/master` (#7/#10/#14 code fixes hold
under real conditions). Emergency Stop is a confirmed product **FAIL**, not a harness artifact —
needs a fix that resolves/kills the specific pending tool-call gate process, not just the
dispatch-level run record.
