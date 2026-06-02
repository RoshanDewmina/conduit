# WS-8 — Security & privacy review

> Run **after WS-3 lands** (it audits the finished key code). Audit + surgical fixes only; no broad refactors. Not a 17-point item — a release gate for an app that handles private keys.

## Context
Conduit handles **private keys, passphrases, passwords, and host trust**. Repo `/Users/roshansilva/Documents/command-center`, branch off `feat/warp-style-agent-blocks`. Build: `cd Packages/ConduitKit && swift build`. Read `CLAUDE.md`, `docs/agent-contract.md`. The security foundation is reportedly strong (Keychain-only secrets, real TOFU, biometric gating, 0 `try!`) — your job is to confirm that and find the gaps, especially in the new WS-3 key-import code.

## Review checklist
1. **Secret-leak scan.** `grep -rniE "print\(|os_log|NSLog|debugPrint|dump\(" Packages/ConduitKit/Sources/SecurityKit Packages/ConduitKit/Sources/KeysFeature` and the connect path; inspect every hit near key/passphrase/password vars. Confirm `KeyStore`, `OpenSSHKeyParser`, `KeyImportView`, `CredentialResolver` never leak secrets to logs, error strings, UserDefaults, files, or analytics/Sentry.
2. **Keychain / Secure Enclave.** Correct accessibility class (`whenUnlockedThisDeviceOnly`, non-synced unless intended); `BiometricGate` actually gates sensitive ops; nothing syncs to iCloud unintentionally.
3. **TOFU / host-key.** Prod paths keep the trust-on-first-use prompt; debug auto-trust is `#if DEBUG`/env-guarded and cannot reach Release. Host key re-verified on reconnect (cross-check WS-1).
4. **Transport.** No silent downgrade to weak ciphers/MACs/kex if configurable; known-hosts persistence integrity-protected.
5. **Pasteboard / screenshots.** Paste-import doesn't leave the key on the general pasteboard longer than needed; consider excluding sensitive screens from screenshots.
6. **Logs / observability.** Sentry/crash logs + the observability batch scrub secrets and host details.
7. **Privacy manifest.** `PrivacyInfo.xcprivacy` declarations match actual data + required-reason API usage (coordinate with WS-7).
8. **Dependencies.** Quick audit of the SSH/crypto deps (incl. the forked `Wellz26/swift-nio-ssh`) for known-bad versions.

## Constraints
- Minimal, surgical fixes. File anything you can't safely fix as a ranked finding. · Don't weaken existing security to simplify.

## Acceptance
- `SECURITY-REVIEW.md` (in `docs/` or this folder): findings ranked **Critical/High/Medium/Low**, each with file:line, impact, and fix-or-recommendation. · Critical/High fixed with regression tests, or an explicit reason they can't be fixed now. · Build + suite green after fixes.

## Report Template (fill in, return)
```
## WS-8 Report
### Secret-leak scan: <commands run; clean? findings>
### Keychain/Enclave: <findings>  · TOFU/host-key: <prod prompt intact? debug guard ok?>
### Transport: <findings>  · Pasteboard/screenshots: <findings>
### Logs/observability scrubbing: <findings>  · Privacy manifest: <accurate?>
### Dependency audit (incl. NIO-SSH fork): <findings>
### Findings: Critical __ High __ Med __ Low __ (see SECURITY-REVIEW.md)
### Fixes applied + tests: <list>  · Build/Suite: <green/red, count>
### Deviations/risks:
```
