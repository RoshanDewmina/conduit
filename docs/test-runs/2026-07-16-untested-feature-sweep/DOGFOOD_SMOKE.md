# Dogfood smoke — owner iPhone (2026-07-16 post-merge)

**Audience:** Roshan (owner phone dogfood)  
**Updated:** 2026-07-16 ~17:22 ET (phone `"Hi"` launched after auth fix); build line corrected ~19:50 ET  
**Build:** at the 17:22 smoke the phone ran `ec3565f7`; later installs same day ended at `62b4424d` (see DOGFOOD_READY install history). Host `lancerd` from merged PR #145 (`1a51329b`)  
**Superseded by:** `DOGFOOD_DEVICE_WALKTHROUGH.md` (evening owner walkthrough @ `62b4424d` — approve/Proof/Policy/Audit/follow-up verdicts live there)  
**Device:** Roshan's iPhone `557A7877-F729-5031-9606-0E04F2B67822`  
**App:** Reinstalled ~16:34 ET (`dev.lancer.mobile`); foregrounded ~17:19 via `devicectl`

---

## Result: **PASS** (auth + phone launch) — UI transcript screenshot not captured

| Gate | Status | Evidence |
|---|---|---|
| Production daemon | OK | Reloaded ~17:17 ET; Homebrew `PATH` in plist; doctor 12 OK, relay **confirmed** |
| Phone paired | **PASS** | Code **149884** kept across reload; no remint |
| Auth preflight | **PASS** | Host RPC launched @ 21:19:07Z; phone `"Hi"` @ 21:20:25Z — both `conversation-append-launched allow` (no auth-preflight deny) |
| Smoke send→approve (phone) | **PASS** (launch) | Audit `conversation-append-launched allow` command `Hi` @ `2026-07-16T21:20:25Z`; no escalate in following window |
| No stale "Couldn't get a reply" | **LIKELY PASS** | Dispatch launched; idb could not screenshot physical UI |

---

## Root cause (17:05 deny)

Launchd cold `claude auth status --json` measured **~13s** under a gui LaunchAgent vs production probe budget **20s**. Interactive shell was logged-in and fast (~1s); resident deny was `errClaudeAuthUnavailable` (timeout), audited as `conversation-append-auth-preflight` deny — not a real logout.

Code: `claude_auth.go` (`claudeAuthProbeTimeout`, `claudeAuthPreflight` / `ensureClaudeAuth` → `dispatch.go` conversation-append path).

## Fix applied (host)

1. Probe timeout **20s → 35s**
2. Boot-time background auth cache warm (`resident.go`)
3. Resolve real `claude` excluding `~/.lancer/bin` shim (`resolveClaudeAuthBin` / `lookPathInExcluding`)
4. `lancerd install` writes Homebrew-first `PATH` into launchd plist (preserves `APPROVAL_RELAY_SECRET`)
5. Reinstalled + reloaded LaunchAgent — **pairing kept**, no remint

---

## Pair log (unchanged)

- Code **149884** paired **2026/07/16 17:02:56**
- Post-reload doctor: relay pairing **confirmed** on `wss://conduit-push.fly.dev`

---

## Smoke log

| # | Step | Result |
|---|---|---|
| 1 | Pair | **PASS** (149884; kept across daemon reload) |
| 2a | Host auth/launch proof | **PASS** — `conversation-append-launched allow` @ 21:19:07Z for `Reply with exactly: auth-preflight-ok…` |
| 2b | Phone send | **PASS** — `"Hi"` → `conversation-append-launched allow` @ 21:20:25Z |
| 3 | Approve | **N/A** — no escalate for this turn in audit window |
| 4 | Follow-up | optional |

**Prior deny (historical):**
```json
{"timestamp":"2026-07-16T21:05:24Z","action":"conversation-append-auth-preflight","agent":"claudeCode","kind":"dispatch","command":"Hi","effect":"deny","rule":"default:ask"}
```

**Host proof after fix:**
```json
{"timestamp":"2026-07-16T21:19:07Z","action":"conversation-append-launched","agent":"claudeCode","kind":"dispatch","command":"Reply with exactly: auth-preflight-ok. Do not run any tools.","effect":"allow","rule":"default:ask"}
```

---

## Owner phone retry (now)

1. Confirm Trusted Machines still **Connected** (do **not** remint unless doctor shows unpaired).
2. Send: `List files in the current directory, then stop.`
3. Approve if asked.
4. Pass bar: audit `conversation-append-launched` (not auth-preflight deny); no **Couldn't get a reply — No connected machine**.

```bash
tail -f ~/.lancer/audit.log ~/.lancer/lancerd.stderr.log
```

---

## Prior mint history

| Code | Mint (ET) | Outcome |
|---|---|---|
| 758455 | 16:53 | Expired; no pair |
| **149884** | ~16:58 | **Paired 17:02:56** (still the live identity) |
