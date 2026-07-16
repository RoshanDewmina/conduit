# Untested-feature live sweep — Phase 4 GAP LIST (Wave 1 code merged; merge→master + dogfood)

**Date:** 2026-07-16  
**Tip:** `integration/2026-07-16-untested-sweep` @ `b8bb778c` (FX merges land at ancestor `7707e4fa`)  
**Worktree:** `.worktrees/untested-sweep-2026-07-16`  
**Evidence root:** `docs/test-runs/2026-07-16-untested-feature-sweep/`  
**Session chain:** Claude `941bc90d` → Cursor C3/F-final → Claude Fable `3ddbf98e` (Wave 1) → Cursor Grok continuation (merge + gates) → owner-ordered merge→master + phone dogfood (~16:29 ET).

---

## Owner digest (1 page)

### What this sweep proved

Live XCUITest + isolated-daemon lanes exercised 24 previously-untested surfaces against a tip that merges the night WP fixes with Orca terminal. Two **real P0 daemon bugs** were found, fixed, reviewed, and merged on this branch:

1. **F1 (`4e45dbaa`)** — first-send approval silently dropped when relay re-pair was mid-flight; `sendApproval` now bounded-retries.
2. **F4 (`1f08c3c6` / `ec425b40`)** — approve recorded but CLI never launched; resume path now launches on approve. **C3 live-proved** a real `claude` run + `474f104 sweep edit` commit after approve.

**Wave 1 code (2026-07-16 ~16:10 ET)** merged into tip after unit gates (`go test ./...` green; `swift test` 781+62+13):

3. **FX7 (`a7749650` → merge `543566ba`)** — client treats sync `needsApproval` as awaiting-approval + polls same runID (unblocks #7 UI chain).
4. **FX5 (`a8a91761` → merge `2a872e1e`)** — pairing Connect pinned above number pad (#5).
5. **Lane P (`4382f1b8`+`7b4d4695` → merge `7707e4fa`)** — relay audit tail + coarse permission mode; YAML rules stay SSH-gated (#2/#3 product decision implemented).

### Top product gaps still open

| Pri | Gap | Verdict source |
|---|---|---|
| P0/P1 | **#7/#8/#9/#17/#23 live re-proof owed** — FX7 merged + unit-gated; Lane C4 must re-run the F4 approve→turn chain and confirm review/receipt UI binds | code FIXED; live C4 |
| P0 | **#2/#3 live re-proof owed** — Lane P relay mirror merged + unit-gated; Settings Policy/Audit over relay-only still needs XCUITest | code FIXED; live C4 |
| P1 | **Background-tasks pill never appeared** on a completed Bash turn (no tool chip either) | LD2 + LF-final #10 FAIL |
| P1 | **#5 Connect occlusion** — code FIXED (FX5); keypad screenshot proof still owed in C4 | code FIXED; visual C4 |
| P2 | Emergency Stop mechanically reachable but never cleanly PASS under harness timing | LA2 #1 BLOCKED |
| P2 | Mid-run feedback / tool-dedup / todo checklist still harness-BLOCKED | LD2 + LF-final #11/#14/#18 |

### What passed (live)

Onboarding gate · composer dispatch picker · inline approval card · pending-approvals banner · permission-mode pill · pairing timeout 30s · Agents tap→continuable Chat · thread-list filters/customize · thread-list metadata · PR detail honest-empty · repo name≠cwd plumbing · **F4 approve→launch (daemon)** · **Terminal open + real usage (F-final)**.

### C3 / F-final / Wave 1 status

C3 + F-final **completed** (`LC3-report.md`, `LF-final-report.md`). Wave 1 **merged + unit-gated**; **Lane C4 live sim re-test still owed**.

---

## Ranked candidate scoreboard (canonical)

Best available verdict per candidate. Prefer A2/C2/D2/C3/F-final/LB over earlier lanes when both exist.

| # | Candidate | Best verdict | Lane | Notes |
|---|---|---|---|---|
| 1 | Emergency Stop | **BLOCKED** (harness) | LA2 | UI reachable; "No connected host" under re-pair race |
| 2 | Policy editor | **FIXED** (code) / live owed | Lane P | Relay coarse permission-mode picker; YAML stays SSH |
| 3 | Audit feed | **FIXED** (code) / live owed | Lane P | `agentAuditTail` relay arm |
| 4 | Pending-approvals banner | **PASS** | LB | |
| 5 | First-run onboarding | **PASS** (+ Connect **FIXED** code) | LB + FX5 | C4 screenshot still owed |
| 6 | Inline approval card | **PASS** | LB | Real git commit landed |
| 7 | Review pill → sheet | **FIXED** (code) / live owed | LC3 + FX7 | Was stale needsApproval error; awaiting-approval path merged |
| 8 | FileViewerView | **BLOCKED** → retest via C4 | LC3 | Was blocked on #7 UI |
| 9 | AddCommentSheet | **BLOCKED** → retest via C4 | LC3 | Was blocked on #7 UI |
| 10 | Background-tasks pill | **FAIL** | LD2 + LF-final | Reconfirmed: turn done, pill absent |
| 11 | Mid-run feedback queue | **BLOCKED** (harness) | LD2 + LF-final | followup send never enabled mid-run |
| 12 | Permission-mode pill | **PASS** | LB | |
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

## Fixes landed this sweep (on `integration/2026-07-16-untested-sweep`)

| Fix | Commit | Status |
|---|---|---|
| F1 approval delivery retry | `065481d9` → merge `4e45dbaa` | Merged; live-proven by C2/D2/C3 |
| F4 approve→launch resume | `ec425b40` → merge `1f08c3c6` | Merged; unit + **C3 live CLI + git commit** |
| Pairing timeout 8s→30s | `d1f8559a` | Merged into tip |
| F2 addrepo truncation | — | **Drop** (false bug narrative) |
| F3 pairing disagreement | doc branch `36310671` | No product fix; env artifact — confirmed by F-final terminal PASS |
| FX7 needsApproval → awaiting | `a7749650` → merge `543566ba` | Merged; unit-gated; **C4 live owed** |
| FX5 Connect above keypad | `a8a91761` → merge `2a872e1e` | Merged; **C4 screenshot owed** |
| Lane P policy/audit relay | `4382f1b8`+`7b4d4695` → merge `7707e4fa` | Merged; unit-gated; **C4 live owed** |
| Drop sentry Package.resolved pin | `faeb80c9` | Merged (FX7 contamination cleanup) |

---

## Remaining work (ordered)

1. **Merge-to-master + push** — owner-ordered 2026-07-16 ~16:29 ET (supersedes prior C4-wait autonomy stop). In progress this session.
2. **Owner phone dogfood** — install tip on UDID `557A7877-…`, re-pair if needed, run `DOGFOOD_READY.md` §4 smoke → write `DOGFOOD_SMOKE.md`.
3. **Lane C4 live sim re-test** (parallel, Simurgh `lease-197`): #7 chain (#8/#9/#17/#23) + #2/#3 Policy/Audit over relay + FX5 keypad screenshot + #10/#14 recheck + #1/#11/#18 harness retries. Code FIXED for #2/#3/#5/#7; live still owed.
4. **#10/#14 product diagnosis** if C4 still fails pill/chip hydration (`fx10-bg-tasks` worktree in flight — do not merge until green).

---

## Lane file index

| File | Role |
|---|---|
| `LA-report.md` / `LA2-report.md` | Governance — HID then XCUITest |
| `LB-report.md` | Onboarding / composer / approvals |
| `LC-report.md` / `LC2-report.md` / `LC3-report.md` | Review stack — F1 then F4 then post-F4 UI gap |
| `LD-report.md` / `LD2-report.md` | Chat pills / thread list |
| `LE-report.md` / `LF-final-report.md` | Terminal — FAIL under contention → PASS light load |
| `GAP_LIST.md` | This synthesis |
| `screenshots/` | Per-lane PNG evidence |

**Incident:** accidental bare `lancerd pair` rotated `~/.lancer/relay-pairing.json` to fly.dev code `310440`; production daemon reconnected. Owner phone re-pair may be needed (L6 already owner-gated).
