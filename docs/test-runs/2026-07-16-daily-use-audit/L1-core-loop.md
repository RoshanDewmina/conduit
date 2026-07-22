# L1 — Core loop (pair → dispatch → approval → approve → continue → follow-up → hook exit 0)

**Date:** 2026-07-16  
**Auditor:** L1 Core Loop (daily-use audit)  
**Worktree tip:** `/Users/roshansilva/Documents/command-center/.worktrees/daily-use-audit-2026-07-16` @ `b17b6172`  
**Sim UDID:** `095F8B3A-FEA3-4031-A2A5-561755740730` (iPhone 17 Pro, Booted)  
**App:** `/tmp/daily-use-audit-dd/Build/Products/Debug-iphonesimulator/Lancer.app` (`dev.lancer.mobile`)  
**Resident daemon:** pid `81742` (`~/.lancer/bin/lancerd daemon`)  
**Relay:** `wss://conduit-push.fly.dev`  
**Evidence-only:** no product code changes.

---

## Summary (PASS/FAIL per §3 substep)

| Substep | Result |
|---|---|
| Pair | **PASS** |
| Dispatch | **PASS** |
| Approval card (sent to phone) | **PASS** (daemon `sent approval`; UI card fleeting due to DEBUG auto-approve) |
| Approve | **PASS** |
| Agent continues | **PASS** |
| Same-thread follow-up | **PASS** |
| Hook exit 0 after approve | **PASS** (functional; see caveat) |

**Parallel L2/L3/L4 may start:** **YES** — paired sim + dispatch attempt succeeded with evidence.

---

## 1) Pair — PASS

### Orchestrator code 587341 (expired / unusable for this session)

- File at start: `/tmp/daily-use-audit-pair-code.txt` → `587341` (mtime Jul 16 05:15).
- Daemon after orchestrator pair window:

```text
2026/07/16 05:15:38 e2e: connected to relay as daemon
2026/07/16 05:17:18 e2e: paired with phone
```

- `relay-pairing.json` still had `code=587341` with `confirmedAt=2026-07-16T09:17:18Z` when re-checked later.
- Re-launch with `LANCER_RELAY_PAIR_CODE=587341` **failed** phone-side:

```text
2026-07-16 05:27:07.488 E  Lancer[…] [dev.lancer.mobile:E2ERelayClient] handleMessage: relay error: key mismatch -- pairing already established with a different key
```

- UI (OCR `L1-05-after-45s.png`): `Couldn't get a reply` / `No connected machine. Pair one in Settings → Trusted Machines.`

### Re-pair (code 587341 expired >5min; allowed) — orphan warning recorded

Command (no `--help`):

```bash
~/.lancer/bin/lancerd pair
```

Verbatim excerpt from `/tmp/daily-use-audit-pair-out.txt`:

```text
lancerd: REPLACING existing relay pairing identity — phones on the previous identity are orphaned and must re-pair
…
Pairing code: 583514
```

Daemon:

```text
lancerd daemon: relay pairing identity changed — dropping the previous relay session; phones on it are orphaned until re-paired
2026/07/16 05:28:37 e2e: connected to relay as daemon
```

Phone launch with new code:

```bash
CODE=583514
env \
  SIMCTL_CHILD_LANCER_RELAY_PAIR_CODE="$CODE" \
  SIMCTL_CHILD_LANCER_DESTINATION=liveThread \
  SIMCTL_CHILD_LANCER_LIVETHREAD_PROMPT='List the files in the current directory, then stop.' \
  SIMCTL_CHILD_LANCER_LIVETHREAD_CWD='/Users/roshansilva/Documents/command-center/.worktrees/daily-use-audit-2026-07-16' \
  SIMCTL_CHILD_LANCER_LIVETHREAD_FOLLOWUP='Now count how many .swift files there are.' \
  SIMCTL_CHILD_LANCER_DEBUG_APPROVAL_DECISION=approve \
  SIMCTL_CHILD_LANCER_SKIP_CURSOR_ONBOARDING=1 \
  xcrun simctl launch 095F8B3A-FEA3-4031-A2A5-561755740730 dev.lancer.mobile -- -onboardingSeen YES
```

Daemon pair proof:

```text
2026/07/16 05:30:21 e2e: paired with phone
```

`relay-pairing.json` after: `code=583514`, `confirmedAt=2026-07-16T09:30:21Z`.

Screenshots: `screenshots/L1-01-trusted-machines.png` (pre-re-pair deep link; OCR sparse), `screenshots/L1-06-pair-dispatch-t10s.png`.

**Race note:** `ShellLiveBridge.waitForConnectedMachine` default timeout is **8s**; auto-pair took ~21s from launch, so first `liveThread` send failed with “No connected machine” even though pair completed moments later (`L1-10`, `L1-11`).

---

## 2) Dispatch — PASS

After pair was live in-memory, **idb** tap on Retry (HID noted broken; idb companion worked on this UDID):

```bash
idb ui describe-all --udid 095F8B3A-FEA3-4031-A2A5-561755740730
# Retry AXFrame ≈ {{20, 296.67}, {35.67, 17}}
idb ui tap --udid 095F8B3A-FEA3-4031-A2A5-561755740730 38 307
```

Screenshot after tap (`L1-12-after-idb-retry.png` OCR): **Working**.

Audit:

```json
{"timestamp":"2026-07-16T09:36:06Z","action":"conversation-append-launched","agent":"claudeCode","kind":"dispatch","command":"List the files in the current directory, then stop.","effect":"allow","rule":"default:ask","approvalId":"ebcca325-7e96-45ce-afe7-1651bad99190",...}
```

Phone DB conversation:

```text
conv_d853e1ff-391a-4cdf-8d2f-62a6c44fb620 | List the files in the current directory, | …/daily-use-audit-2026-07-16 | active | 2026-07-16 09:36:06.991
```

---

## 3) Approval card — PASS (daemon send; UI card not held)

Daemon:

```text
2026/07/16 05:36:13 e2e: sent approval 311e597f-30ce-4353-a0d6-5bdf8a1bf6e6 over relay
2026/07/16 05:36:29 e2e: sent approval a97af13c-7b5e-4c12-a9cd-17872f2abb24 over relay
```

Audit escalate (gated tool):

```json
{"timestamp":"2026-07-16T09:36:13Z","action":"escalate","agent":"claudeCode","kind":"command","command":"ls -la","effect":"ask","rule":"default:ask","approvalId":"311e597f-30ce-4353-a0d6-5bdf8a1bf6e6",...}
```

**UI card screenshot:** not captured — `LANCER_DEBUG_APPROVAL_DECISION=approve` decided ~1s later via the same `RelayApprovalIngest.decide` path as the Approve button (`LiveThreadView` DEBUG seam). Treat daemon `sent approval` + audit `escalate` as the card-delivery proof.

---

## 4) Approve — PASS

```json
{"timestamp":"2026-07-16T09:36:14Z","action":"approve","agent":"claudeCode","kind":"command","command":"ls -la","rule":"default:ask","approvalId":"311e597f-30ce-4353-a0d6-5bdf8a1bf6e6",...}
{"timestamp":"2026-07-16T09:36:29Z","action":"approve","agent":"claudeCode","kind":"command","command":"find . -name \"*.swift\" -type f | wc -l","rule":"default:ask","approvalId":"a97af13c-7b5e-4c12-a9cd-17872f2abb24",...}
```

Path: DEBUG env → production `approvalIngest.decide(..., .approved)` (not a policy bypass).

---

## 5) Agent continues — PASS

Transcript OCR (`L1-13`, `L1-14`, `L1-15`, `L1-20`): directory listing after the user prompt (`.claude/`, `Packages/`, `daemon/`, …).

Phone DB turn 0:

```text
conversation_id=conv_d853e1ff-… ordinal=0 status=completed asst_len=1013
asst starts: "Here are the files and directories in the current directory:"
```

Receipt (chat_artifacts):

```text
runId=ebcca325-7e96-45ce-afe7-1651bad99190 exitCode=0 status=completed
commands[0]={command: 'ls -la', kind: 'shell', startedAt: '2026-07-16T09:36:13Z'}
```

---

## 6) Same-thread follow-up — PASS

`LANCER_LIVETHREAD_FOLLOWUP` fired after first terminal reply (DEBUG seam → `bridge.sendFollowUp`).

Audit:

```json
{"timestamp":"2026-07-16T09:36:22Z","action":"conversation-append-launched","agent":"claudeCode","kind":"dispatch","command":"Now count how many .swift files there are.","effect":"allow",...,"approvalId":"e5f2e730-352f-4176-8e64-29579ffa9d94",...}
```

Phone DB — **same** `conversation_id`, ordinal 1:

```text
conv_d853e1ff-391a-4cdf-8d2f-62a6c44fb620 | 1 | Now count how many .swift files there are. | completed | asst="There are **413 .swift files** in this repository."
```

Second receipt: `runId=e5f2e730-… exitCode=0`, command `find . -name "*.swift" -type f | wc -l`.

Screenshots: `L1-20-post-loop.png`, `L1-21-followup-scrolled.png`, `L1-22-followup-turn.png` (scroll attempt; listing still dominant in OCR — DB is authoritative for follow-up text).

---

## 7) Hook exit 0 after approve — PASS (functional; process exit not instrumented)

**Not observed:** a live shell line `HOOK_EXIT=0` from `lancerd agent-hook` (hooks run inside the agent session; `lancerd.stderr.log` only shows `sent approval`, not hook process exits — same observability gap the night run hit).

**Observed chain that proves allow/exit-0 behavior after approve:**

1. `escalate` `ls -la` at `09:36:13Z` for approvalId `311e597f-…`
2. `approve` same id at `09:36:14Z`
3. Agent emitted directory listing in transcript / turn 0 `completed`
4. Receipt lists shell command `ls -la` and run `exitCode: 0`
5. Queue empty after: `queue.json` → `{"pending": []}`

Deny/non-zero hook exit would not yield tool output + completed turn. Marking **PASS** on that functional bar; flag under Warnings that raw hook process exit was not captured.

---

## Screenshots written

| Path | Notes |
|---|---|
| `screenshots/L1-00-relaunch.png` | pre-existing (orchestrator) |
| `screenshots/L1-01-trusted-machines.png` | trustedMachines deep link |
| `screenshots/L1-02-dispatch-t8s.png` | liveThread before connected |
| `screenshots/L1-03-after-repair-t10s.png` | key-mismatch era |
| `screenshots/L1-04-mid-loop.png` | no-machine error |
| `screenshots/L1-05-after-45s.png` | no-machine + Retry |
| `screenshots/L1-06-pair-dispatch-t10s.png` | after code 583514 launch |
| `screenshots/L1-07-mid-t30s.png` | still racing |
| `screenshots/L1-08-mid-t60s.png` | still racing |
| `screenshots/L1-09-after-120s.png` | no-machine after race |
| `screenshots/L1-10-paired-before-redispatch.png` | paired in daemon; UI still errored |
| `screenshots/L1-11-pre-retry.png` | Retry coords |
| `screenshots/L1-12-after-idb-retry.png` | **Working** after Retry |
| `screenshots/L1-13-working-t10s.png` | listing streaming |
| `screenshots/L1-14-t20s.png` | listing |
| `screenshots/L1-15-t30s.png` | listing |
| `screenshots/L1-20-post-loop.png` | post-loop listing |
| `screenshots/L1-21-followup-scrolled.png` | scroll attempt |
| `screenshots/L1-22-followup-turn.png` | scroll attempt |

---

## Blockers for L2–L4

- **None for starting** L2/L3/L4: sim is paired (`583514` confirmed) and one full dispatch loop passed.
- **Operational notes (not blockers):**
  - Prefer idb (or XCUITest) over bare HID; idb worked here.
  - `liveThread` + auto-pair races `waitForConnectedMachine(8s)` — pair-first then Retry/dispatch is more reliable.
  - Re-using an old confirmed pairing code after phone identity drift → `key mismatch`; mint fresh `lancerd pair` (orphans prior phones).

---

## Verification

- SwiftPM: skipped (audit)
- Xcode app target: cite build SUCCEEDED from `/tmp/daily-use-audit-xcodebuild.txt` → line `14362:** BUILD SUCCEEDED ** [278.243 sec]`
- Go daemon: cite go test PASS from `/tmp/daily-use-audit-go-test.txt` → `ok lancer/lancerd 49.851s` ; `ok lancer/lancerd/policy 0.288s`
- Hook/resident bridge: cite prove/fail for exit 0 → **PASS (functional)** — approve then tool output + receipt `exitCode:0`; raw `HOOK_EXIT=$?` not instrumented
- Owner-gated: N/A for L1
- Warnings: phone orphaned by pair `587341` (orchestrator) and again by re-pair `583514`; DEBUG auto-approve used (production decide path); first liveThread send lost to 8s connect race (recovered via idb Retry)

