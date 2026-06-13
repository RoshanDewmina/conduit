# Security Triage — App-Store Publish Readiness

**Date:** 2026-06-13
**Reviewer:** Claude Sonnet 4.6 (agent-acba4089)
**Scope:** Packages/ConduitKit/Sources, daemon/ (conduitd, push-backend, agent-runner)
**Prior baseline:** docs/SECURITY-REVIEW.md (WS-8, 2026-05-31)

---

## Summary Table

| Area | Severity | Status | Finding |
|---|---|---|---|
| Test vectors — private keys in test file | LOW | ACCEPTED | SSH test key PEM blobs are deliberate test vectors; test-only, not shipping code |
| Dockerfile — root process (agent-runner) | LOW | OPEN | `agent-runner` container runs as root; no `USER` directive |
| Dockerfile — root process (push-backend) | LOW | OPEN | `push-backend` container runs as root; no `USER` directive |
| exec.Command — dispatch.go | LOW | CLEAN | `agentArgv` builds explicit argv (no shell); `exec.Command(argv[0], argv[1:]...)` is safe |
| exec.Command — agent-runner/main.go | LOW | CLEAN | argv deserialized from JSON; `exec.CommandContext(ctx, argv[0], argv[1:]...)` — no shell |
| exec.Command — process_provider.go | LOW | CLEAN | `runnerPath` comes from env (operator-controlled), not user input |
| Open redirect — billing.go:267 | LOW | FALSE POSITIVE | Target is hardcoded `conduit://` scheme; only `session_id` query-param is appended (URL-escaped); not an open redirect |
| HTTP server without TLS — push-backend | LOW | MITIGATED | `fly.toml` sets `force_https = true`; Fly.io edge terminates TLS; `ListenAndServe` on 8080 only receives proxied traffic |
| http:// in OrbstackProvisioner | INFO | ACCEPTED | `#if DEBUG`-gated; talks to loopback (OrbStack local API) only |
| http:// in PreviewKit | INFO | ACCEPTED | Generates a localhost URL for curl over SSH tunnel; NSAllowsLocalNetworking covers this; shell-metas validated + single-quote-escaped |
| APPROVAL_RELAY_SECRET unset warning | MEDIUM | OPEN | Backend logs a SECURITY WARNING at startup when the env var is absent; control-plane endpoints are unauthenticated without it |
| TOFU auto-trust in production paths | PASS | CLOSED | Auto-trust only in `#if DEBUG && os(iOS)` files; TOFUHostKeyValidator always prompts in Release |
| Fail-closed policy | PASS | CLOSED | `hookShouldHold` returns true for all mutating kinds when daemon is down; policy engine defaults to `ask` when doc.Default is empty |
| Secret logging — Swift | PASS | CLEAN | Zero hits in Sources/ near password/secret/token/key variables |
| Secret logging — Go daemon | PASS | CLEAN | Only run IDs and agent IDs logged; CONDUIT_OPENROUTER_KEY not logged |
| Audit log redaction — Go | PASS | CLEAN | `redactSecrets()` called on every command field before write; patterns cover sk-/gh-/bearer/api-key forms |
| Audit log redaction — Swift | PASS | CLEAN | `AuditEvent` stores only structured metadata (no raw credentials) |
| NSAllowsArbitraryLoads | PASS | CLEAN | Info.plist only has `NSAllowsLocalNetworking: true`; no arbitrary loads |
| BiometricGate lockout | PASS | CLOSED | LOW-2 from WS-8 is fixed: `.biometryLockout` now falls back to `deviceOwnerAuthentication`, not silent success |
| Keychain accessibility | PASS | CLEAN | `whenUnlockedThisDeviceOnly`, `kSecAttrSynchronizable: false` (confirmed by prior review) |
| Redactor patterns — Swift | PASS | CLEAN | Anthropic, OpenRouter, OpenAI, AWS, GitHub tokens covered; MEDIUM-2 from WS-8 resolved |
| PEM cleared after import | PASS | CLOSED | MEDIUM-1 from WS-8 resolved; `pemText` zeroed immediately on success |

---

## Semgrep Results

**Version:** 1.165.0
**Config:** `--config auto --severity ERROR --severity WARNING`
**Targets:** Packages/ and daemon/ (362 git-tracked files)
**Findings:** 11 total — 9 ERROR, 2 WARNING

### By Rule

| Rule | Severity | Files | Verdict |
|---|---|---|---|
| `generic.secrets.detected-private-key` | ERROR×4 | `OpenSSHKeyParserTests.swift` | FALSE POSITIVE — deliberate test vectors |
| `dockerfile.missing-user-entrypoint` | ERROR×2 | `agent-runner/Dockerfile`, `push-backend/Dockerfile` | REAL — LOW severity |
| `go.dangerous-exec-command` | ERROR×3 | `dispatch.go`, `agent-runner/main.go`, `process_provider.go` | FALSE POSITIVE — explicit argv, no shell interpolation |
| `go.open-redirect` | WARNING×1 | `push-backend/billing.go:267` | FALSE POSITIVE — target is hardcoded `conduit://` scheme |
| `go.use-tls` | WARNING×1 | `push-backend/main.go:125` | MITIGATED — Fly.io TLS termination enforced by `force_https = true` |

---

## Detailed Findings

### FINDING-1 — Dockerfiles run as root (agent-runner and push-backend)

**Semgrep rule:** `dockerfile.security.missing-user-entrypoint`
**Files:**
- `daemon/agent-runner/Dockerfile:22`
- `daemon/push-backend/Dockerfile:13`

**What:** Neither Dockerfile adds a `USER` instruction before the `ENTRYPOINT`. The binary runs as UID 0 inside the container.

**Why it matters:** If either container is compromised (e.g. via a dependency vulnerability in the Claude Code CLI npm package bundled in agent-runner, or a future RCE in push-backend), the attacker starts with root inside the container. Container escapes are more achievable from root. The agent-runner container also executes user-specified agent commands (claude, codex, opencode), which widens the blast radius.

**Recommended fix:**
```dockerfile
# agent-runner Dockerfile (after the COPY line)
RUN adduser --disabled-password --gecos '' conduit
USER conduit
```
Same pattern for push-backend. Note: the npm global install of `@anthropic-ai/claude-code` must happen before `USER conduit` (root required for global install), or use `--prefix /home/conduit/.npm-global` with `PATH` adjustment.

**Severity:** LOW (container isolation still applies; not exploitable from outside without a prior code path into the container)

---

### FINDING-2 — APPROVAL_RELAY_SECRET unset at deployment is silently operational

**File:** `daemon/push-backend/relay_security.go:138`

**What:** When `APPROVAL_RELAY_SECRET` is not set in the environment, the push-backend's control-plane endpoints (`/register`, `/approval`, `/run-complete`) are unauthenticated. The code logs a startup `SECURITY WARNING` but continues running. The per-session `relayToken` (Tier 2) still guards `/approval/decision` and `/decisions`, so cross-session decision spoofing is not possible, but the control-plane registration endpoint is open.

**Why it matters:** Without `APPROVAL_RELAY_SECRET`, any party that can reach the push-backend (it is publicly reachable on Fly.io) can call `/register` to overwrite a session's APNs device token or relayToken, effectively hijacking approval push notifications for any known session ID.

**Current state:** The finding `fix-backend-relay-auth.md` in `docs/audit/findings/` documents this as a known blocker (B2) that was addressed by adding Tier 2 per-session tokens. The Tier 1 secret requirement is documented but its absence is not enforced at startup (the server starts regardless).

**Recommended fix:** Either fail-fast at startup when `APPROVAL_RELAY_SECRET` is empty in a production environment (check a `CONDUIT_ENV=production` or `FLY_APP_NAME` guard), or document the Fly.io secret-required deployment step prominently in runbooks. The actual deployment using `fly secrets set` should include this variable.

**Severity:** MEDIUM — OPEN (infrastructure/operational; not a code bug, but a deployment gate that should be enforced)

---

### FINDING-3 — exec.Command findings (semgrep false positives — confirmed safe)

**Files:** `dispatch.go:53`, `agent-runner/main.go:51`, `process_provider.go:20`

**Assessment (all three):** Semgrep flags these because `exec.Command` receives non-static values. Manual inspection confirms each is safe:

- **dispatch.go:** `agentArgv()` builds `[]string{"claude", "-p", prompt}` via a `switch` on whitelisted agent names; `exec.Command(argv[0], argv[1:]...)` is passed this pre-validated slice. No shell involved.
- **agent-runner/main.go:51:** `argv` is deserialized from `CONDUIT_COMMAND_ARGV` (a JSON array provided by the control plane operator, not end-users). The call is `exec.CommandContext(ctx, argv[0], argv[1:]...)` — explicit argv.
- **process_provider.go:20:** `runnerPath` comes from `CONDUIT_RUNNER_PATH` env var (operator-set) or defaults to the literal `"agent-runner"`. No user input reaches this call.

**Verdict:** All three are FALSE POSITIVES. No shell injection risk.

---

### FINDING-4 — Open redirect semgrep finding (false positive — confirmed safe)

**File:** `daemon/push-backend/billing.go:267`

**Code:**
```go
func handleBillingReturn(w http.ResponseWriter, r *http.Request) {
    sessionID := r.URL.Query().Get("session_id")
    deepLink := "conduit://billing/complete"
    if sessionID != "" {
        deepLink += "?checkoutSessionId=" + url.QueryEscape(sessionID)
    }
    http.Redirect(w, r, deepLink, http.StatusFound)
}
```

**Assessment:** The redirect target is hardcoded to the `conduit://` custom URL scheme. The only user-controlled input (`session_id`) is appended as a URL-escaped query parameter to that fixed prefix. There is no path to redirect to an attacker-controlled domain. The semgrep rule fires because `r` appears in scope, but `r` is only used to extract the query parameter, not to construct the redirect domain.

**Verdict:** FALSE POSITIVE. No open redirect risk.

---

### FINDING-5 — HTTP server without TLS (semgrep finding — mitigated by deployment)

**File:** `daemon/push-backend/main.go:125`

**Code:** `log.Fatal(http.ListenAndServe(":"+port, corsMiddleware(mux)))`

**Assessment:** The Go server binds plain HTTP on port 8080. However, `daemon/push-backend/fly.toml` contains `force_https = true` under `[http_service]`, which causes Fly.io's edge proxy to enforce HTTPS and reject plain HTTP from external callers. Internal traffic between the Fly.io edge and the container is over the private mesh. All production traffic is effectively TLS-terminated at the edge.

**Verdict:** MITIGATED in the documented Fly.io deployment. A code-level note in `main.go` documenting the TLS-termination expectation would be a low-cost hardening improvement. Not a blocker.

---

## Cross-Check Against docs/SECURITY-REVIEW.md (WS-8, 2026-05-31)

| WS-8 Finding | Status in Current Code |
|---|---|
| MEDIUM-1: PEM not zeroed after import | **CLOSED** — `pemText = ""` added immediately after Keychain write |
| MEDIUM-2: Redactor missing Anthropic key pattern | **CLOSED** — `("Anthropic key", "sk-ant-[A-Za-z0-9\\-_]{20,}")` present in `Redactor.swift` |
| LOW-1: No .privacySensitive() on KeyImportView/KeysView | **OPEN** — no change since WS-8; still flagged for a UX-privacy pass |
| LOW-2: BiometricGate silent success on biometryLockout | **CLOSED** — `.biometryLockout` now falls back to `deviceOwnerAuthentication`; fail-closed if passcode not satisfied |
| LOW-3: autoTrustHostKey runtime-settable (not compile-guard) | **OPEN** — parameter still exists on `LiveTerminalModel.init`; production callers (Session flow via `SSHSession.connect`) do not use it; only `DebugTerminalHarness.swift` (gated `#if DEBUG && os(iOS)`) passes `true` |
| LOW-4: TOFU not re-verified in DebugSessionHarness reconnect | **CLOSED** — confirmed `#if DEBUG && os(iOS)` gate; no production exposure |
| LOW-5: Redactor missing PEM blobs and Bearer tokens | **OPEN** — `Redactor.swift` still lacks `-----BEGIN OPENSSH PRIVATE KEY-----` and `Bearer` / JWT patterns |
| LOW-6: PrivacyInfo SystemBootTime reason cross-check | **CLOSED** — Sentry DSN is `""`, SDK never starts; PrivacyInfo removed CrashData/SystemBootTime per FABLE_REPORT |
| LOW-7: Wellz26/swift-nio-ssh fork CVE audit | **OPEN** — still using the community fork; no change since WS-8; risk remains low |

---

## Assessment of 4 Core Security Properties

### 1. TOFU Host-Key in Production: PASS

- `TOFUHostKeyValidator` always fails with `ConduitError.hostKeyUnknown` for unknown fingerprints in production; the UI then shows a confirmation sheet.
- Auto-trust (`autoTrustHostKey: true`) is only reachable through `DebugTerminalHarness.swift` and `DebugSessionHarness.swift`, both of which are wrapped in `#if DEBUG && os(iOS)` at the file level.
- The `passwordSession(autoTrustHostKey:)` factory method has a default of `false`; no production caller passes `true`.
- LOW-3 from WS-8 (no compile-time guard on the parameter) is still technically open, but the runtime exposure is zero.

### 2. Fail-Closed Policy: PASS

- `hookShouldHold(kind, risk)` in `hook.go` returns `true` for all mutating kinds (`command`, `patch`, `fileWrite`, `fileDelete`, `network`, `credential`, and all unrecognized kinds) when the daemon socket is unreachable.
- Read-only kinds only fail-open when `CONDUIT_HOOK_READONLY_FAIL_OPEN=1` is explicitly set — off by default.
- The policy engine (`policy/evaluate.go`) defaults to `EffectAsk` when `doc.Default` is empty — never `allow`.
- `waitWithTimeout` in `approval.go` returns `hookDecision{decision: "deny"}` on timeout — the backstop is always deny.
- `TestHookMutatingDeniedWhenDaemonDown` and `TestCommandHookHeldWhenDaemonDown` exercise this path.

### 3. No Secret Logging: PASS

- Swift `Sources/` — zero matches for `print(`/`NSLog(`/`os_log(` near password/secret/token/credential/key variable names.
- Go daemon — logging in `conduitd/` and `agent-runner/` only logs run IDs, agent IDs, and error messages. `CONDUIT_OPENROUTER_KEY` is passed to child env but never appears in a `log.Printf` call.
- `push-backend` logs session IDs and boolean flags (`apns=true/false`, `relay=true/false`) — not device tokens or relay tokens.
- `audit.go`'s `redactSecrets()` runs on every `command` field before it reaches the log file.
- **Gap (inherited LOW-5 from WS-8):** `Redactor.swift` on the Swift side does not redact PEM blobs or Bearer tokens. Risk is low (user must paste a key into the terminal and then trigger AI context capture), but remains open.

### 4. No Insecure Network Endpoints in Production: PASS (with notes)

- `NSAllowsArbitraryLoads` is absent from Info.plist; only `NSAllowsLocalNetworking: true` is set.
- `OrbstackProvisioner` uses `http://127.0.0.1:28935` — gated `#if DEBUG`.
- `PreviewKit` constructs a localhost URL for `curl` over an SSH tunnel — covered by `NSAllowsLocalNetworking`.
- `push-backend` listens on plain HTTP 8080 internally, but Fly.io enforces `force_https = true` for all external traffic. No external HTTP exposure.
- `HostedAgent.downloadURL` accepts both `https://` and `http://` in `storageRef`. The URL is opened via `openURL()` in `AgentRunDetailView` (Safari handoff). If the control plane ever returns an `http://` artifact URL, iOS Safari will follow it. This is a low-risk data-channel issue (artifact download, not credential transport), and ATS with `NSAllowsLocalNetworking` would block non-local `http://` URLs at the `URLSession` level anyway.

---

## Go / No-Go

| Property | Verdict |
|---|---|
| TOFU host-key prompt in production | **PASS** |
| Fail-closed approval policy | **PASS** |
| No secret logging | **PASS** |
| No insecure network in production | **PASS** |

**Overall verdict: GO for App Store submission** on the four core security properties.

Two OPEN operational items should be resolved before or shortly after launch:
1. **FINDING-2 (MEDIUM)** — Enforce `APPROVAL_RELAY_SECRET` at push-backend startup in production, or document `fly secrets set` as a required pre-launch step with a startup check.
2. **LOW-5 (inherited)** — Add PEM blob and Bearer token patterns to `Redactor.swift` for defence-in-depth.

The two Dockerfile root-process findings (FINDING-1) are LOW severity and can be addressed in a follow-up hardening pass post-launch.
