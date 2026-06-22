# Verification rubric (for the orchestrator / judge)

Aligned to the source plan's §II-D judge protocol. When a subagent's report is pasted back, I judge here — **against the live repo, not the report's claims.** Agents over-report success; trust only what reproduces.

## Verdict scale
- **PASS** — acceptance met, independently verified, safe to merge.
- **PASS-WITH-NITS** — mergeable; minor follow-ups listed.
- **FAIL** — acceptance unmet, claims unverifiable, scope violated, or an invariant/regression broke. Return a numbered fix list.

## Universal checks (§II-D, every workstream)
1. **Builds** — `cd Packages/LancerKit && swift build` green, no new warnings. Report says green ⇒ confirm; red ⇒ FAIL.
2. **Scope** — only the brief's files touched. `git diff --stat` on the agent's branch; stray files (esp. from `git add -A`) ⇒ FAIL.
3. **Invariants** — TOFU prompt intact in prod (debug auto-trust `#if DEBUG`/env-guarded only); single unified PTY (no second `SSHShell`); `.submitted`-only TUI escalation in `SessionViewModel.onBlockBytes`; Keychain-only secrets.
4. **Tests** — `swift test` green; new coverage where claimed; **count not reduced**. A dropped count = deleted tests = FAIL unless justified.
5. **Visual** — light+dark gallery/live screenshot for any UI change. None ⇒ can't pass a UI workstream.
6. **No regressions** — spot-check the §II-C confirmed behaviors the change could plausibly break.
7. **Verdict + fix list.** Owner merges only on PASS.

## Red flags → deeper scrutiny
- "Tests pass" with no count, or count dropped. · "Build green" but diff shows obvious errors.
- Security/billing workstream claiming "no issues" with no command evidence.
- UI workstream with no screenshots. · Any "live SSH / sim test" claim with no command shown.
- Edits outside stated scope. · A secret value appearing anywhere in the diff.

## Per-workstream judging keys
- **WS-0:** `.gitignore` now covers every dotfile + `build/` + the Linux binary (`git status` no longer lists them). Per-file decision log for the 4 tracked edits. Untracked key files left for WS-3 (not deleted). Clean status reproduced.
- **WS-1 (LEAD, highest risk):** In the diff confirm `reconnectEngine` is actually *initialized and wired* in `connect()` (source says it was declared-but-never-set); PTY re-opens on unexpected `shell.bytes` finish; keepalive has a real timeout that flips `isConnected`; `BlockRepository.recent()` is now called on reconnect; `map(error:)` is type-based not string-matched. New transport tests run without a live network.
- **WS-2:** #1 — inline-TUI min-height floor (`ToolCardView.swift:69–78`) no longer applies to idle/short blocks. #3 — long output no longer silently overwrites at 2000 rows (`BlockRenderer.swift:297`) — scrollback or truncation UI added. #2/#5 — check whether commit 858b688 already shipped the COLORFGBG theme hint; if so the agent should *verify/close* it, not duplicate. Invariants held.
- **WS-3 (security-critical):** Independently grep for secret logging: `grep -rniE "print\(|os_log|NSLog|debugPrint" Packages/LancerKit/Sources/SecurityKit Packages/LancerKit/Sources/KeysFeature` and inspect hits near key/passphrase vars. Parser tests cover Ed25519/RSA, OpenSSH+PEM, passphrase, malformed, wrong-type, empty — not just happy path. Storage is Keychain (`whenUnlockedThisDeviceOnly`), not UserDefaults/files. Import UI never re-renders key material.
- **WS-4:** `billing.go` routes complete past ~L100 (checkout/portal/webhook/return all return real responses; webhook verifies the Stripe signature). `isPro` DEBUG bypass (`PurchaseManager.swift:34–41`) cannot return true in Release. Stripe CLI local test shown. No live secret keys committed.
- **WS-5:** Hardcoded IP gone from `LancerApp.swift:14` → build-config HTTPS URL. Cloud Run deploy + Secret Manager + `.p8` volume mount described/run; APNs key path matches `APNS_KEY_PATH`. Remote-notification handler returns `.newData` + posts the notification. Dead provisioner stubs removed or gated. **No `.p8`/secret committed.**
- **WS-6:** `/subscribe` server-side redirect to the backend `/billing/checkout` works; `/privacy` exists (App Store requires the URL); `BACKEND_URL` is server-only, not client-exposed. Build succeeds.
- **WS-7:** Sentry DSN wired at `LancerApp.swift:20` (DSN itself is owner-supplied — confirm the plumbing, not the secret). `project.yml` entitlements swapped (L57–63) and `xcodegen generate` regenerates cleanly. Debug affordances (`isPro`, `DebugSeeder`, REVIEW pill) gated out of Release. Metadata finalized in `docs/app-store-*`. Owner-only steps clearly separated.
- **WS-8:** Re-run the secret-leak greps yourself. Spot-check 2–3 findings in `SECURITY-REVIEW.md` against actual file:line — real? Critical/High fixed-with-tests or explicitly deferred-with-reason. Privacy manifest declarations match actual API/data usage.
- **WS-9:** Open screenshots (light+dark). Fixed-geometry invariant: PixelBox doesn't shift between rows (`ZStack(.trailing).frame(width:20)`). `.system` fonts replaced with DS in `AgentIsland`/`AgentStatusHeader`/`FilesView`. a11y labels present (`grep .accessibilityLabel`/`.accessibilityHidden`); terminal Dynamic Type capped at `accessibility3`; Reduce Motion respected. Sync/Billing stub rows hidden where required.
- **WS-10:** QA report has pass/fail + repro + screenshot per item; §8.6 (background→reconnect, Wi-Fi↔cellular handoff, scrollback) actually exercised on a real device+host, not just sim.

## My verdict output format
```
## Verdict: <PASS | PASS-WITH-NITS | FAIL> — WS-<n>
### Independently ran: <build/test/grep results I reproduced>
### Matches report? <yes / discrepancies>
### Acceptance: <each criterion met/unmet>
### Invariants: <each relevant one: held/broken>
### Issues: <ranked, file:line>
### Fix list (if not PASS): <numbered, specific>
### Merge: <merge / merge after nits / iterate>
```
