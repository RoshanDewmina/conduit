# Governed Approvals v1 — Pre-submission Audit: Go push-backend (relay + hosted engine)

**Scope:** `daemon/push-backend/*.go` (APNs approval push relay, governed-approvals **decision relay**, hosted-agents cloud engine). Cross-component context read in `daemon/conduitd/{decision_poll,server,approval}.go` and `Packages/ConduitKit/Sources/SessionFeature/ApprovalRelay.swift`.
**Branch:** `feat/governed-approvals` (worktree `governed-approvals-audit`).
**Owner:** Go reviewer-and-fixer — I both reviewed AND implemented fixes in the Go backend. `conduitd`/Swift items are FLAGGED (I do not own Swift; `conduitd` items noted where a Go change there is the right home).
**Go:** go1.26.4. **Method:** adversarial pass (disprove each candidate as reachable/already-guarded before acting), then low-risk fixes + table-driven tests, run to green under `go vet` / `go test` / `go test -race`.

Paths are repo-relative to the worktree root.

## Final status (details + raw output at the bottom)
- `go vet ./...` → **clean**
- `go test ./...` → **ok** (57 top-level tests, 85 incl. subtests)
- `go test -race ./...` → **ok**
- Baseline before changes was also green; no pre-existing test was weakened.

---

## HIGHEST-PRIORITY VERIFICATION — the decision relay (phone POSTs a decision, conduitd polls it)

Contract (confirmed end-to-end):
- Phone → `POST /approval/decision {approvalId, decision, sessionId, editedToolInput?}` (`ApprovalRelay.swift:112-123`, no auth header sent).
- conduitd → `GET /decisions?sessionId=...`, server **drains** the bucket, conduitd calls `approvalStore.resolve(id, decision, edited)` per record (`decision_poll.go:71-82`).

Result of the 6 mandated checks:
1. **EXACTLY ONCE** — drain-on-poll gives *at-most-once*; **double-apply on a phone re-POST was possible** (the old handler appended duplicates) → **FIXED** (dedupe by `approvalId`). `conduitd.approvalStore.resolve` is independently idempotent (delete-under-lock, `approval.go:74-89`), so double-apply is now blocked at both layers. A *lost* decision (conduitd polls, then crashes before applying) **fails safe**: conduitd's 120 s wait elapses → auto-deny (`server.go:565`, `approval.go:91-98`).
2. **NO SPOOF / NO REPLAY** — **AUTH IS ABSENT** on the decision POST and the poll (and on `/register`, `/approval`, `/run-complete`). This is the **BLOCKER** below. Stale-id replay is a no-op (resolve returns `false` for an unknown/已-resolved id), but a *live* forged `approve`/`approveAlways` for a known `sessionId` is applied verbatim.
3. **FAIL SAFE** — unknown session on POST now still 204s into a bucket (by design, conduitd may register later) but is bounded/auth-gated; unknown decision verbs are now **rejected** (were silently relayed); malformed/oversized bodies → 400; secrets (APNs key, device/JWT tokens) are never logged. **FIXED/verified.**
4. **CONCURRENCY** — all shared-map access is under `decisions.Mutex` / `registry.RWMutex`; added a contention test; `-race` clean. Unbounded map growth + no TTL/eviction **FIXED**. No goroutine leaks (janitor is a single long-lived ticker, like the existing reaper/schedule tickers).
5. **INPUT VALIDATION** — body-size caps + required-field + length checks added to every relay handler. **FIXED.**
6. **Hosted engine** — Stripe webhook signature verification is **SOUND**; all privileged endpoints are authenticated; credit math is safe. One real TOCTOU on the run-concurrency quota **FIXED**; an agent-quota TOCTOU **FLAGGED**; webhook body cap **FIXED**. Details below.

---

## BLOCKER

### [BLOCKER][security] Decision relay has no authentication — cross-session approval spoofing bypasses the entire governance feature
`daemon/push-backend/decisions.go:75` (`handlePostDecision`), `:131` (`handlePollDecisions`); also `main.go:125` (`handleRegister`), `:188` (`handleApproval`), `:218` (`handleRunComplete`).

**Issue.** The relay trusts a caller-supplied `sessionId` as both the routing key *and* the implicit capability. There is no credential binding "who may post/poll decisions for this session". Concretely, against the single shared deployment (`conduit-push.fly.dev`):
- Anyone who learns a `sessionId` can `POST /approval/decision {sessionId, approvalId, decision:"approveAlways"}`. conduitd's poller applies it (`decision_poll.go:80-82`) and the agent's gated command executes — a full bypass of the human-in-the-loop approval.
- Anyone can `GET /decisions?sessionId=...` and **drain** another session's decisions (DoS: the real conduitd never sees the user's "approve" → the approval times out; plus disclosure of `approvalId`/`decision`/`editedToolInput`).
- `POST /register` lets anyone overwrite the APNs device token for a session (redirect/suppress push).

`sessionId` is **not** a usable secret even though it may be high-entropy: it is sent in APNs payloads, used as a `GET` query parameter (proxy/access logs), echoed in `/approval`, and logged at register. It is a routing id, not a bearer credential.

**Reachability.** Direct, unauthenticated, internet-reachable HTTP. This is the "security-blind fallback that postdates the security review" — confirmed.

**Fix status: FLAGGED (full fix) + PARTIAL MITIGATION IMPLEMENTED (safe, merge-ready).**
- The complete fix is a **per-session capability token** and *requires a coordinated change across components I do not own*: the iOS app (Swift) and `conduitd` must establish a per-session secret over their already-authenticated SSH channel and present it (e.g. `Authorization: Bearer <sessionToken>`) on register/post/poll; the backend binds `sessionId → token` at first register (reject mismatches, fail-closed) and constant-time-compares on every mutate/drain. I did **not** ship a fake "optional" per-request check, because optional auth on a security boundary is bypassable (an attacker simply omits it) — that would be "weakening security to make it work."
- What I shipped server-side **now**, all behind no behavioural change to existing clients:
  - An **optional shared-secret guard** (`relay_security.go:46` `relayAuthorized`, env `APPROVAL_RELAY_SECRET`, constant-time compare via `crypto/subtle`). When set, all five relay endpoints require the bearer secret; when unset, behaviour is unchanged and `main()` logs one loud startup `SECURITY WARNING` (`relay_security.go:warnIfRelayUnauthenticated`, wired in `main.go`). This stops anonymous internet callers once ops + clients are wired. **It is explicitly NOT the full fix** — a single shared secret cannot distinguish one legitimate client from another, so it does not prevent a cross-session spoof by a party already holding the secret. The per-session token above is still required. Enabling it needs conduitd (`server.go:postApprovalPush`, `decision_poll.go`) and the app (`ApprovalRelay.swift`) to send the header — a coordinated rollout.
  - **Input hardening** that closes the spoof's force-multipliers regardless of auth: body caps, field-length caps, decision allow-list, dedupe, TTL/eviction, size caps (MAJOR/MINOR items below).

**Recommendation for ship gate:** treat per-session-token auth as a release blocker for the decision relay, or disable the poll/POST fallback in production until it lands (the SSH `agent.approval.response` path in `server.go:350-363` is authenticated by the SSH channel and is unaffected).

---

## MAJOR

### [MAJOR][dos] Unbounded in-memory growth of the decision and device maps (no TTL, no eviction, no cap)
`daemon/push-backend/decisions.go` (`decisions.bySession`), `main.go:31` (`registry.tokens`).

**Issue.** The original code appended decisions forever and never evicted device registrations. On unauthenticated endpoints an attacker can flood unique `sessionId`s (and, knowing one, unique `approvalId`s) to exhaust memory; even in normal use, decisions for sessions that never poll and tokens for dead sessions accrue without bound.

**Reachability.** Direct via the unauthenticated endpoints (compounds BLOCKER-1).

**Fix status: FIXED.**
- TTL eviction: `decisionTTL = 5m`, `evictExpiredDecisionsLocked` (`decisions.go:57`) is run on every post/poll (lazy, full-map sweep) and by a background janitor.
- Device TTL: `deviceTokenTTL = 24h`, `evictExpiredDevices` (`main.go:173`) via the janitor; `registry.seen` now stamps each registration.
- Hard caps: `maxDecisionsPerSession = 64`, `maxDecisionSessions = 4096`, `maxRegisteredDevices = 100000` — over-cap posts return 429/503 instead of growing.
- `startRelayJanitor` (`main.go:158`) is a single long-lived ticker (sweeps every minute), started from `main()` only (no goroutine leak; not started under tests, which call the eviction helpers directly).

### [MAJOR][dos] No request-body size limits on unauthenticated relay handlers (and the Stripe webhook)
`daemon/push-backend/relay_security.go:64` (`decodeRelayJSON`), `billing.go:215` (`handleBillingWebhook`).

**Issue.** Every handler used `json.NewDecoder(r.Body)` (or `io.ReadAll` for the webhook) with no cap → a single large body is buffered into memory; trivial DoS on the unauthenticated relay.

**Reachability.** Direct.

**Fix status: FIXED.** `decodeRelayJSON` wraps the body in `http.MaxBytesReader(w, r.Body, 64KiB)` for all four relay JSON handlers and returns a generic 400 (no decoder internals leaked). The Stripe webhook now caps at 1 MiB before `io.ReadAll` and returns 413 over-cap (signature verification still runs on the bounded payload). I deliberately scoped caps per-handler rather than globally so legitimately large hosted-engine bodies (run-log batches) are unaffected.

### [MAJOR][correctness] Phone re-POST created duplicate decision records (no dedupe by id)
`daemon/push-backend/decisions.go:104-124` (dedupe + caps in `handlePostDecision`).

**Issue.** The old handler unconditionally `append`ed, so a phone retry (the relay is best-effort, app may resend) produced two records for one `approvalId`; a single poll returned both and called `resolve` twice. conduitd's `resolve` is idempotent so the *second* call is a no-op today — but that's a fragile cross-component dependency and the prompt requires relay-level dedupe.

**Reachability.** App resends decisions on the no-live-channel path (`ApprovalRelay.swift:73`); plausible on flaky mobile networks.

**Fix status: FIXED.** Idempotent-by-`approvalId`: a re-POST replaces the prior record (keeping the latest verb) rather than appending. Locked test `TestDecisionRelayDedupeByApprovalID`.

### [MAJOR][conduitd / FLAGGED] Poll-applied decisions skip the audit record and the `approveAlways` policy write
`daemon/conduitd/decision_poll.go:80-82` (calls `p.resolve(...)` and **ignores** the `(event, ok)` result).

**Issue.** The authenticated paths record a human decision in the audit log and persist `approveAlways` to policy (`server.go:356-362` for RPC, `:567-571` for the SSH wait). The **poll fallback does neither** — it only unblocks the agent. So a decision delivered via the relay is missing from the audit trail, and `approveAlways` chosen on the phone (while no SSH channel is attached) is applied once but **not** saved as an always-rule.

**Reachability.** Any decision made on the phone while conduitd has no live SSH channel (the exact scenario the relay exists for).

**Severity nuance.** Fails *safe* for policy (a dropped always-rule means more prompting later, never less), but the **audit gap is a real governance defect** for a product whose value is the approval trail.

**Fix status: FLAGGED (not fixed — it's a `conduitd` change and crosses the poller/server boundary).** Recommended: give the poller a callback into the server so a poll-resolved event runs `recordHumanDecision` and, for `approveAlways`, `policy.appendAllowAlways` — mirroring `handleMessage`'s `agent.approval.response` case. Low-risk, ~15 lines, but it changes `conduitd` wiring and warrants its own review; I did not silently rewrite it.

---

## MINOR

### [MINOR][correctness/fail-safe] Decision verb was not validated — garbage relayed downstream
`daemon/push-backend/decisions.go:49` (`validDecision`), enforced in `handlePostDecision`.
**Issue.** Any string was accepted as `decision`. conduitd coerces non-`approve*` to `deny` (`server.go:581-585`), so a typo/garbage verb silently becomes a deny — and arbitrary values flow through. **Fix status: FIXED** — allow-list `{approve, approveAlways, deny}`, else 400. Test `TestDecisionRelayValidatesDecisionVerb`.

### [MINOR][correctness] Quota TOCTOU on concurrent runs — check-then-append outside the lock
`daemon/push-backend/agents.go:297` (in-lock recheck), `quotas.go:108` (`countActiveRunsForCustomerLocked`).
**Issue.** `handleCreateRun` called `enforceQuota(quotaCheckRun)` (which `RLock`s, counts, unlocks) and only later took the write lock to append. Two simultaneous creates could both pass and both append → exceed `QUOTA_MAX_CONCURRENT_RUNS` (each concurrent cloud run is real compute $). **Reachability:** two in-flight `POST /runs` for one customer. **Fix status: FIXED** — re-check the count *inside* the write-lock critical section before appending; equivalent to the existing check in sequential paths (no test breakage), closes the concurrent window.

### [MINOR][correctness / FLAGGED] Same TOCTOU exists for the agent-count quota
`daemon/push-backend/agents.go:103-166` (`handleCreateAgent`).
**Issue.** Symmetric to the run quota. **Fix status: FLAGGED, not fixed** — `handleCreateAgent` provisions external resources (OpenRouter sub-key, runtime) *before* taking the lock, so a naive in-lock recheck that rejects after provisioning would **orphan** those resources. The correct fix is reserve-then-provision (or provision-then-reconcile-on-reject), which is a larger change than this audit's low-risk bar. Impact is bounded (agent count is a soft limit, not direct compute) and acceptable to defer with this note.

### [MINOR][hardening] `/register` accepted empty/oversized fields and silently clobbered tokens
`daemon/push-backend/main.go:125` (`handleRegister`).
**Issue.** Empty `sessionId`/`deviceToken` created junk map entries; no length bound. (The unauthenticated *overwrite* of an existing session's token is part of BLOCKER-1.) **Fix status: FIXED (validation + caps)** — required-field + length checks + capacity guard; test `TestHandleRegisterValidation`.

---

## VERIFIED SOUND (adversarial pass — no change needed)

- **Stripe webhook signature verification** — `billing.go:400` `verifyStripeSignature`: parses `t`/`v1`, enforces a 5-min timestamp tolerance, recomputes `HMAC-SHA256(secret, "t.payload")`, compares with `hmac.Equal` (constant-time), and **fails closed when `STRIPE_WEBHOOK_SECRET` is unset**. `handleBillingWebhook` verifies *before* parsing/acting. Correct.
- **Auth on privileged hosted-engine endpoints** — every `/agents`, `/runs`, `/usage`, `/billing/{credits,quota}`, `/orgs`, `/schedules` handler derives identity server-side from the bearer client-token (`entitlements.go:334` `resolveEntitlementFromBearer`, customerId is never taken from client input) and enforces ownership via `resourceVisibleToEntitlement` (`orgs.go:175`). Runner callbacks (`/runs/{id}/logs|control`, `PATCH /runs/{id}`) use per-run scoped tokens (`run_logs.go:94`), validated against the path id. No missing-auth or IDOR found.
- **Credit math** — `credits.go:107` `deductCredits`: load→mutate→save under `creditsStore.mu`; prepaid floored at 0, overage tracked separately, `cost<0` rejected at the usage handler (`usage.go:66`), `cost==0` short-circuits. No under/overflow path (float64; rounding is not a security issue).
- **conduitd idempotency** — `approval.go:74-89` `resolve` deletes under lock and returns `false` on a second call; combined with relay dedupe, decisions apply at most once.

---

## Tests added (all table-driven where natural; `daemon/push-backend/`)
- `decisions_test.go`:
  - `TestDecisionRelayValidatesDecisionVerb` — allow-list (approve/approveAlways/deny accepted; `yolo`/`APPROVE`/`""` → 400).
  - `TestDecisionRelayDedupeByApprovalID` — re-POST collapses to one record carrying the latest verb.
  - `TestDecisionRelayRejectsMissingFields` — expanded to a 4-case table (each required field).
  - `TestDecisionRelayPollRejectsMissingSession` — poll w/o `sessionId` → 400.
  - `TestDecisionRelayRejectsOversizedBody` — body > 64 KiB → 400 (MaxBytesReader).
  - `TestDecisionRelayRejectsOversizedField` — under body cap, over field cap → 400.
  - `TestDecisionRelayPerSessionCap` — 64 distinct ids OK, 65th → 429.
  - `TestEvictExpiredDecisions` — TTL sweep keeps fresh, drops stale.
- `relay_security_test.go` (new):
  - `TestRelaySharedSecretEnforced` — with `APPROVAL_RELAY_SECRET` set: POST/poll w/o or wrong bearer → 401; correct → 204/200.
  - `TestHandleRegisterValidation` — 6-case table (ok / missing / empty / oversized session / oversized token).
  - `TestRelayConcurrentAccess` — 64×{post,poll,register} goroutines; proves locking under `-race`.
  - `TestEvictExpiredDevices` — device TTL sweep keeps fresh, drops stale.
- Existing `TestDecisionRelayPostThenPoll` / `TestHandleApproval*` retained and still green (drain-on-poll + routing semantics unchanged).

## Files changed
- New: `relay_security.go`, `relay_security_test.go`.
- Modified: `decisions.go`, `decisions_test.go`, `main.go` (registry+janitor+handlers+CORS `Authorization`), `billing.go` (webhook body cap), `quotas.go` (locked counter), `agents.go` (run-quota in-lock recheck).

## Final verification output
```
$ go vet ./...            # (cwd: daemon/push-backend)
<clean>

$ go test ./...
ok      conduit/push-backend    1.030s

$ go test -race ./...
ok      conduit/push-backend    2.074s
```
57 top-level tests pass (85 including subtests); vet clean; race clean. Baseline was green before the changes.
