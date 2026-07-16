# Dogfood smoke — owner iPhone (2026-07-16 post-merge)

**Audience:** Roshan (owner phone dogfood)  
**Updated:** 2026-07-16 ~17:20 ET (auth-preflight fix landed on host; phone send retry owed)  
**Build:** app still `origin/master` @ `ec3565f7` (FX7 + FX5 + Lane P + FX10); **host `lancerd`** rebuilt from `fix/auth-preflight-cold-probe` and reinstalled  
**Device:** Roshan's iPhone `557A7877-F729-5031-9606-0E04F2B67822`  
**App:** Reinstalled ~16:34 ET (`dev.lancer.mobile`); brought to foreground ~17:19 via `devicectl`

---

## Result: **AUTH GREEN / phone smoke BLOCKED on owner tap**

| Gate | Status | Evidence |
|---|---|---|
| Production daemon | OK | Reloaded ~17:17 ET; plist now has Homebrew `PATH`; doctor 12 OK, relay **confirmed** |
| Phone paired | **PASS** (kept) | Code **149884** @ 17:02:56; **no remint**; doctor still `paired with relay wss://conduit-push.fly.dev (confirmed)` after reload |
| Auth preflight | **PASS** | Host RPC `agent.conversations.append` → audit `conversation-append-launched` **allow** @ `2026-07-16T21:19:07Z` (no auth-preflight deny) |
| Smoke send→approve (phone) | **BLOCKED** | Physical idb cannot attach (`FBDeviceSet: []`); needs owner send on phone |
| No stale "Couldn't get a reply" | **HOST PROVEN** / phone owed | Host launch succeeded; phone UI not driven |

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
| 2b | Phone send | **BLOCKED** — owner tap: Workspaces → Claude → send low-risk prompt |
| 3 | Approve | **OWED** if ask card appears |
| 4 | Follow-up | **OWED** after phone send |

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
