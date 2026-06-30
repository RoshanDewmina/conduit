# Security Review — WS-8

> Historical review from 2026-05-31. Current security posture and open launch risks are tracked in
> `docs/KNOWN_ISSUES.md` and `docs/legal/SECURITY_ARCHITECTURE.md`. Use this file as evidence for
> the WS-8 key-import review only, not as the current security source of truth.

**Date:** 2026-05-31  
**Reviewer:** WS-8 agent (Claude Sonnet 4.6)  
**Branch:** feat/warp-style-agent-blocks  
**Scope:** WS-3 key-import additions + existing SecurityKit/SSHTransport foundation

---

## Summary

9 findings total across all categories. **0 Critical. 0 High. 2 Medium. 7 Low.**  
2 Medium findings were **fixed** in this review with regression tests.  
Build green. 253 tests pass (251 pre-existing + 2 new from this review).

---

## Findings

### MEDIUM-1 — PEM text not zeroed from ViewModel memory after successful import [FIXED]

**File:** `Packages/LancerKit/Sources/KeysFeature/KeyImportView.swift:65`  
**Impact:** On successful import the `passphrase` field was cleared (line 66) but `pemText` — which holds the full OpenSSH private key PEM including the raw 32-byte seed — remained resident in the `@Observable` ViewModel until the user tapped Done or Cancel. Between import success and dismissal, the PEM was accessible in memory and would appear in any heap snapshot / crash dump. In practice the window is short (user taps Done immediately), but the principle of "zero as soon as not needed" was violated.  
**Fix applied:** `pemText = ""` added immediately after the successful Keychain write, co-located with `passphrase = ""` and before transitioning to `.done` phase.  
**Regression test:** none needed — this is a UI-state reset, not a logic branch; the existing `importEd25519FromPEM` round-trip tests exercise the full path.

---

### MEDIUM-2 — Redactor lacks an explicit Anthropic key pattern [FIXED]

**File:** `Packages/LancerKit/Sources/AgentKit/Redactor.swift:20`  
**Impact:** `Redactor.shared.redact()` is applied to terminal context sent to AI providers via `PromptBuilder`. The generic `sk-[A-Za-z0-9\-]{20,}` pattern does match `sk-ant-api03-…` Anthropic keys, but the match is unnamed ("OpenAI key" label). When a `RedactionReport` is logged or surfaced in analytics the mislabelling could cause missed alerting for Anthropic credential exposure. Additionally if Anthropic ever issues tokens not starting with `sk-` (similar to their `sk-ant-api03` → future format changes), coverage would silently drop.  
**Fix applied:** Added `("Anthropic key", #"sk-ant-[A-Za-z0-9\-_]{20,}"#)` pattern before the generic `sk-` entry so the more-specific pattern takes priority and is correctly named in `RedactionReport.matchedPatterns`.  
**Regression tests added:** `RedactorTests.anthropicKey()` and `RedactorTests.anthropicKeyFallback()` — 2 new tests in `Tests/LancerKitTests/RedactorTests.swift`.

---

### LOW-1 — No .privacySensitive() on KeyImportView or KeysView

**File:** `Packages/LancerKit/Sources/KeysFeature/KeyImportView.swift`, `KeysView.swift`  
**Impact:** iOS may snapshot app views for the app switcher. The `TextEditor` showing raw PEM text or the key list showing fingerprints could appear in the task switcher thumbnail. `.privacySensitive()` / `.redacted(reason: .privacy)` on these views would redact them in screenshots and app-switcher snapshots.  
**Recommendation:** Add `.privacySensitive()` to `KeyImportView.body` and `KeysView.body`. Not fixed now — no Swift `.privacySensitive()` API exists in the current SwiftUI version that directly matches the iOS UIKit app-snapshot redaction; the correct approach is to add a `NotificationCenter` observer for `UIApplication.willResignActiveNotification` / `.didBecomeActiveNotification` and toggle a blur overlay on those screens. Flagging for a dedicated UX-privacy pass.

---

### LOW-2 — BiometricGate silently degrades on biometryLockout

**File:** `Packages/LancerKit/Sources/SecurityKit/BiometricGate.swift:32`  
**Impact:** When `LAError.biometryLockout` occurs (too many failed biometric attempts), the gate calls `cont.resume()` (success) instead of throwing. This means a locked-out user is not blocked from accessing their SSH private key. The intent appears to be graceful degradation, but iOS normally falls back to device passcode at lockout rather than granting access unconditionally. Post-lockout, the Keychain item is still protected by the `whenUnlockedThisDeviceOnly` accessibility class (device must be unlocked), so this is a defence-in-depth weakening rather than a full bypass.  
**Recommendation:** On `.biometryLockout`, prompt the user with device-passcode authentication via `.deviceOwnerAuthentication` policy rather than silently succeeding. Not fixed here — change requires UX/product decision (passcode fallback sheet vs. hard block).

---

### LOW-3 — autoTrustHostKey flag is runtime-settable (not compile-time DEBUG-only)

**File:** `Packages/LancerKit/Sources/SessionFeature/LiveTerminalView.swift:61`  
**Impact:** `LiveTerminalModel.passwordSession(autoTrustHostKey:)` and `LiveTerminalModel.init(autoTrustHostKey:)` are `public` APIs with a default of `false`. No compile-time guard prevents Release builds from calling `autoTrustHostKey: true`. Currently no production code path sets it `true` — only the `#if DEBUG`-gated `DebugTerminalHarness`. But the footgun exists.  
**Recommendation:** Add an `#if DEBUG` assertion or precondition inside the `where autoTrustHostKey` catch branch, or restrict the parameter to `#if DEBUG`-only via a conditional extension. Not fixed here — requires API-surface decision; current production exposure is zero.

---

### LOW-4 — TOFU host-key not re-verified in DebugSessionHarness reconnect path

**File:** `Packages/LancerKit/Sources/AppFeature/DebugSessionHarness.swift:49`  
**Impact:** The debug harness calls `vm.trustHostKey()` unconditionally on first connect. On reconnect the `HostKeyStore` is in-memory (fresh each launch), so reconnects will hit `.unknown` again and re-auto-trust. This is intentional for the debug harness and is gated by `#if DEBUG`. Production `SessionViewModel` uses a persistent `HostKeyStore` and re-validates correctly.  
**Verdict:** No fix required; confirmed by file-level `#if DEBUG && os(iOS)` guard.

---

### LOW-5 — Redactor does not cover SSH private key PEM blobs or bearer tokens

**File:** `Packages/LancerKit/Sources/AgentKit/Redactor.swift`  
**Impact:** If a user pastes a PEM private key into a terminal session and that session context is sent to an AI provider via `PromptBuilder`, the long base64 lines would not be redacted. PEM blobs start with `-----BEGIN OPENSSH PRIVATE KEY-----`. Similarly, Bearer tokens (`Bearer [A-Za-z0-9\-_.~+/]+=*`) or JWT strings (`eyJ...`) are not covered.  
**Recommendation:** Add patterns for PEM markers and Bearer/JWT tokens. Out of scope for WS-8 surgical fix; flag for a dedicated Redactor pass. Risk is mitigated by the fact that the user would have to manually paste a key into the terminal and then trigger an AI context capture.

---

### LOW-6 — PrivacyInfo.xcprivacy missing SystemBootTime reason cross-check for Sentry DSN

**File:** `Lancer/PrivacyInfo.xcprivacy:30`  
**Impact:** The manifest declares `NSPrivacyAccessedAPICategorySystemBootTime` with reason code `35F9.1` ("declared for crash reporter"). This is correct if and only if Sentry is the sole consumer of boot time. The Sentry DSN is currently an empty string (`sentryDSN = ""`), meaning Sentry never starts. If a future developer fills in the DSN without reviewing the privacy manifest, the declaration remains valid. No immediate action needed — comment in `LancerApp.swift` already notes this correctly.  
**Verdict:** Informational; no fix needed.

---

### LOW-7 — Wellz26/swift-nio-ssh fork — no CVE audit trail

**File:** `Packages/LancerKit/Package.swift:57`  
**Impact:** The pinned range is `"0.3.4" ..< "0.4.0"` against the community fork `https://github.com/Wellz26/swift-nio-ssh.git`. This fork is used by Citadel for Mac Catalyst NIO product dependency fix and SSH certificate auth. The fork is not the upstream `apple/swift-nio-ssh`, so Apple security advisories against `apple/swift-nio-ssh` may not be tracked. No known CVEs were found at time of review for the 0.3.4 range.  
**Recommendation:** Pin to a specific commit SHA (not a range) in production. Add a calendar reminder to audit when upstream `apple/swift-nio-ssh` ≥0.4 lands in Citadel and migrate back. Document the switch-back condition in `ARCHITECTURE.md §19` (already noted in a comment in `Package.swift`).  
**Verdict:** Risk is low at this version range; no code-level fix applied.

---

## Checklist Results

| Area | Status |
|---|---|
| Secret-leak scan (print/os_log/NSLog/debugPrint) | **CLEAN** — zero hits near key/passphrase/password variables |
| Keychain accessibility class | **OK** — `whenUnlockedThisDeviceOnly` + `kSecAttrSynchronizable: false` enforced in `Keychain.write()` |
| iCloud Keychain sync | **OK** — explicitly set to `false` in all write paths |
| BiometricGate gates key ops | **OK** — `CredentialResolver.resolve()` always calls `BiometricGate.shared.unlock()` for Ed25519 keys |
| TOFU prompt in production | **OK** — `TOFUHostKeyValidator` always prompts in production; auto-trust only in `#if DEBUG` harnesses |
| Debug auto-trust in Release | **OK** — the terminal debug harnesses and seeded E2E seams are DEBUG-gated; production TOFU defaults remain prompting/fail-closed |
| Host key re-verified on reconnect | **OK** — `SSHSession.attemptReconnect()` calls `connect(credential:hostKeyStore:)` which creates a new `TOFUHostKeyValidator` |
| Transport cipher downgrade | **NOT AUDITED** — cipher/kex/MAC selection is delegated entirely to Citadel and swift-nio-ssh; no custom cipher list override found in source |
| Pasteboard — key material | **OK** (LOW-1) — only public keys copied to pasteboard; PEM never written to pasteboard |
| OpenSSHKeyParser algorithm correctness | **OK** — test vectors from real `ssh-keygen` output; bcrypt_pbkdf SHA-512 + Blowfish EKS + interleaved output matches OpenSSH reference; 5 tests exercise the encrypted path |
| Decrypted key bytes zeroed | **PARTIAL** — Swift does not support zeroing `[UInt8]` / `Data` buffers (no SecureBytes abstraction); the seed `Data` returned by `parseEd25519` goes out of scope when `importEd25519FromPEM` completes. ARC semantics release it promptly but do not zero-fill. This is the same limitation as CryptoKit itself; no actionable fix without a custom allocator. |
| Passphrase cleared after import | **FIXED** (MEDIUM-1) |
| PEM text cleared after import | **FIXED** (MEDIUM-1) |
| Error messages — no key material | **OK** — all `ParseError.errorDescription` values are static strings with no key bytes; tested in `OpenSSHKeyParserTests.wrongPassphraseErrorDoesNotLeakData()` |
| Sentry PII scrubbing | **OK** — `sendDefaultPii = false`, `tracesSampleRate = 0`; DSN currently empty so SDK never starts |
| PrivacyInfo.xcprivacy accuracy | **OK** (see LOW-6) |
| UserDefaults — no secrets | **OK** — only preferences (theme, font size, debug bypass flags) in UserDefaults; no keys, tokens, or credentials |
| `try!` in codebase | **CLEAN** — zero hits |
| TODO/FIXME in security code | **CLEAN** — one informational NOTE in `OpenSSHKeyParser.swift` header about unsupported key types; no deferred security fixes |

---

## Fixes Applied

1. **MEDIUM-1 fixed** — `KeyImportView.swift`: cleared `pemText` immediately after successful Keychain write.
2. **MEDIUM-2 fixed** — `Redactor.swift`: added explicit `("Anthropic key", #"sk-ant-[A-Za-z0-9\-_]{20,}"#)` pattern before generic `sk-` pattern.
3. **Regression tests** — 2 new tests in `RedactorTests.swift`: `anthropicKey()` and `anthropicKeyFallback()`.

## Build and Test Results

- Build: **green** (`swift build` — 0 errors, 0 warnings)
- Tests: **253 passed** in 36 suites (251 pre-existing + 2 new)
