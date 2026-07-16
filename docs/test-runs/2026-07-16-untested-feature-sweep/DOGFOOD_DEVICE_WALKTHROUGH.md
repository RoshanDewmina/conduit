# Physical iPhone dogfood walkthrough — 2026-07-16 evening (owner live)

**Audience:** Roshan + agents  
**Session:** Claude Fable (Cowork), worktree `lancer-iphone-dogfood-424a6e`, ~19:20–19:50 ET  
**Build under test:** `origin/master` @ `62b4424d` (PR #149) — the `.app` built 18:05:25 ET; master tip at test time was `ad73e04c` (docs-only past `62b4424d`)  
**Device:** Roshan's iPhone `557A7877-F729-5031-9606-0E04F2B67822`, Lancer `1.0.0 (2)`  
**Host:** production `~/.lancer`, daemon PID 47627 (up since 17:17 ET), relay `wss://conduit-push.fly.dev`, pairing identity `…9884` (never reminted)

Every verdict below is evidenced from THIS session (audit.log lines are UTC; ET = UTC−4).

---

## Verdict table

| # | Step | Verdict | Evidence |
|---|---|---|---|
| 1 | Preflight | **PASS** | doctor 12 OK / 1 warn (shim PATH, pre-existing); `paired with phone` 18:36:29 / 18:48:39 / 19:26:42 / 19:41:44 ET |
| 2 | Tip check | **PASS** (caveat) | Device `devicectl info apps`: Lancer `1.0.0 (2)` = local `.app` (`/tmp/lancer-device-dogfood-dd/...`, mtime 18:05:25) built ~2 min after PR #149 merged 22:03:10Z. Caveat: bundleVersion `2` is static across the day's builds — mtime+timeline is the discriminator, not the version string |
| 3 | All Repos instant paint (#149) | **PASS** | Owner: rows painted immediately on cold reopen. But see WT-C below (return-visit spinner) |
| 4 | Send turn | **PASS** | `conversation-append-launched allow` @ 23:27:24Z for `List files in the current directory, then stop.`; no auth-preflight deny |
| 5 | Approve path | **PASS** | escalate `ls -la` 23:27:29Z → `sent approval f2beb34c… over relay` → approve 23:27:43Z (**14s round trip**) → turn `exited` 0 @ 23:27:45Z; proof receipt written (`lancer.proof/v0`, 1 command) |
| 6 | Proof under ⋯ (#147) | **PASS** | Owner: Proof opens from the ⋯ on the "Worked 19s" row; no inline proof card under every message |
| 7 | Policy over relay (#144 / Lane P) | **PASS** (functional) | Owner: default-decision picker (deny/ask/allow) loads; no stale SSH error flash. Product concern filed as WT-A2 |
| 8 | Audit over relay (Lane P) | **PASS** | Owner: feed loads with tonight's `ls -la` escalate/approve near the top — first live PHONE proof (prior PASS was sim) |
| 9 | FX5 Connect above keypad | **SKIPPED (by design)** | Pairing never broke; no remint. FX5 keeps its C4 sim PASS |
| 10a | Follow-up same thread | **PASS** | Turn ordinal 2 in `conv_baeb2169…`, **same vendor_session_id** `d50a2002…` — true session resume, exited 0 @ 23:41:16Z |
| 10b | Lock-screen push | **FAIL** | Turn 23:42:45Z, escalate `git status` 23:42:49Z, approval sent over relay only; **no APNs push arrived while locked**. Daemon re-sent the pending approval on reconnect (23:43:13 `re-sending 1 pending approval(s) after (re)pair`) and owner approved in-app 23:43:18Z. Loop recovers; push path is dead on this tip |
| 10c | Emergency Stop | **SKIPPED (owner)** | Deferred to a later session; GAP #1 stays BLOCKED |

All three turns tonight exited cleanly (`conversation_turns`: 23:27:45Z / 23:41:16Z / 23:43:21Z, status `exited`).

---

## New findings (WT-*)

| ID | Finding | Severity | Evidence |
|---|---|---|---|
| **WT-A** | **Autonomy pill ("Full bypass") is display-only — not wired to the daemon.** Pill writes `lancer.autonomy.preset` to phone-local `@AppStorage` (`ChatPermissionModePill.swift`); `LancerDProtocol.swift` carries no autonomy field; daemon `policy.PresetDocument("bypass")` (`policy/types.go:84`) is referenced **only by its own test**. `ls -la` escalated under `rule":"default:ask` despite the pill showing Full bypass | **P1** | `WT-05-approval-card-full-bypass.png`; audit 23:27:29Z escalate line; code refs above. Sweep GAP #12 "permission-mode pill PASS" tested rendering, not effect |
| **WT-A2** | **Owner product call:** two overlapping permission controls (global Policy default picker vs per-chat pill) where only the global one works. Owner: per-chat should be the real control ("like everyone else"); kill or demote the global default | design/P1 | Owner statement during step 7 |
| **WT-B** | **Live thread never renders completion:** after approve, "Ran a command" chip stuck on spinner/"Running" and a stale "1 running task" pill, minutes after the daemon recorded exit 0. Re-entering the thread renders correctly (Completed / "Worked 19s") — live event stream stops applying terminal state; persisted data is right | **P1** | `WT-06-completed-turn-stale-running-chip.png` (7:28 PM, run exited 23:27:45Z); re-entry frames in `WT-video-loading-and-menu.mp4` |
| **WT-C** | **Thread-list spinner never resolves on return** to the repo thread list — rows painted (cache paint works) but the header spinner spins indefinitely | P2 | `WT-video-loading-and-menu.mp4` 0–5s |
| **WT-D** | **Top-right ⋯ missing on first entry** into a live thread; appears only after backing out and re-entering | P2 | `WT-video-loading-and-menu.mp4`; owner report |
| **WT-E** | **No APNs push for approvals** (lock-screen test): relay in-app delivery only. Prime suspect: push-backend device-token registry is in-memory and has been redeployed since the 2026-06-23 push-while-closed PASS; needs re-register→push trace on the backend | **P1** | Daemon log 19:42:49/19:43:13 ET (relay sends only, no push confirm); owner observed no lock-screen notification, twice |
| **WT-F** | `ls -la` risk-scored **High** on the approval card — over-rated for a read-only listing; worth a scoring pass | P3 | `WT-05-approval-card-full-bypass.png` |
| **WT-G** | **Audit feed renders oldest-first raw log lines** — top of the feed is 2026-07-11; tonight's entries require scrolling through 5 days of history. Should be newest-first (and ideally structured rows, not raw dump) | P3 | `WT-07-audit-feed-relay.png` (7:50 PM; after one screen of scrolling, still on 2026-07-12) — step 8 stays PASS functionally |

---

## Evidence index

- `screenshots/WT-05-approval-card-full-bypass.png` — approval card (Command `ls -la`, High) with "Full bypass" pill visible (7:27 PM)
- `screenshots/WT-06-completed-turn-stale-running-chip.png` — stale Running chip + "1 running task" after daemon exit (7:28 PM)
- `screenshots/WT-video-loading-and-menu.mp4` — return-visit spinner + missing/reappearing ⋯ (7:31 PM, re-encoded 324K)
- `screenshots/WT-07-audit-feed-relay.png` — Audit feed over relay, oldest-first ordering (7:50 PM)
- Audit chain (UTC): 23:27:24 launch → 23:27:29 escalate → 23:27:43 approve → 23:41:12 follow-up launch → 23:42:45 launch → 23:42:49 escalate → 23:43:18 approve
- Turn ledger: `~/.lancer/conversations.sqlite` `conversation_turns` (3 turns, all `exited`, vendor session `d50a2002…` shared across ordinals 1–2)

## Not claimed

Emergency Stop (skipped), lock-screen push PASS (explicit FAIL above), #7 UI chain / FileViewer / AddComment / Flight Recorder (untouched tonight — still sim-lane work), publish/TestFlight.
