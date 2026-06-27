# WS-10 — Manual QA execution  (final beta gate)

> Run LAST, after the other workstreams merge. Gates the TestFlight beta. Needs a real device + a real remote SSH host (the riskiest paths can't be proven in the simulator). Owner-run or a connected subagent with real credentials.

## Context
Repo `/Users/roshansilva/Documents/command-center`. Read `CLAUDE.md` (visual verification + live block-session harness) and `docs/lancer-test-run-2026-05-30.md` (prior run). Target: iPhone 17 Pro simulator **and** ≥1 real device + 1 real remote host. Screenshot every screen/state in light + dark (`xcrun simctl ui booted appearance dark|light`).

**Focus the energy on what's never been proven:** background→reconnect, Wi-Fi↔cellular handoff, scrollback after reconnect, real-host OSC-133 fidelity across shells, inline `codex` in-block, Live Activity on a real device. These are the launch-readiness risks.

## QA script (execute, log pass/fail + repro + screenshot per item)
1. **Onboarding/gate** — fresh install → biometric gate → onboarding → both CTAs. No clipping; DS fonts.
2. **Auth/keys** — generate Ed25519 (biometric fires), inspect pubkey; **import a key (WS-3): paste + file, good + malformed + passphrase-protected**; store/replace/remove API keys; Test-key good + bad.
3. **Hosts** — add via form and `ssh user@host`; tags; swipe-delete; edit.
4. **Connection** — password-at-connect; **TOFU sheet on first connect** (verify fingerprint, Trust & Connect); 2nd connect no prompt; changed key → mismatch; wrong password → graceful retry (WS-1 #15).
5. **Terminal/blocks (REAL host, across bash/zsh/fish)** — `ls`, failing cmd, ANSI colors, no `~ %` noise, no echoed command; `claude` inline block renders **dark** (WS-2 #2/#5); `vim`/`htop`/`tmux` raw escalation + clean exit; Ctrl-C; long output not silently lost (WS-2 #3); no blank floor on idle blocks (WS-2 #1); collapse/copy/rerun.
6. **Continuation/reconnect (WS-1 — the critical block)** — `sleep 120` → background 15s → reopen still running? Wi-Fi↔cellular mid-session → transparent reconnect? Kill server-side → reconnecting banner + recovery? **Scrollback/history present after reconnect** (WS-1 #14)? 30-min idle survives (WS-1 #13)?
7. **Inbox** — HIGH/MED approvals; Deny/Allow-always/Approve; decided history; **push when backgrounded** (WS-5 — real device, lock screen, Approve from notification).
8. **Billing (WS-4)** — paywall shows when not Pro; StoreKit sandbox purchase unlocks the 6 gated features + multi-host; restore on second install; (US device) Settings→Billing→Manage → conduit.dev/subscribe → Stripe Checkout with test card `4242 4242 4242 4242` → entitlement active.
9. **Settings** — every row; Theme system/light/dark; navigate Snippets/SSH Keys/Terminal; confirm stubbed Sync row hidden (WS-9).
10. **Layout** — every tab light+dark, small + large Dynamic Type, landscape — clipping/overlap/overflow; header placement unified (WS-9); REVIEW pill gone from normal views.
11. **Lifecycle** — force-quit + relaunch (re-gate); airplane mode; low memory; Live Activity / Dynamic Island when backgrounded (real device).

## Acceptance
- Every item logged pass/fail with repro + screenshot. · §6 (reconnect/handoff/scrollback) and §5 (real-host blocks) actually exercised on a real device + host. · Failures filed against the owning workstream with enough detail to fix. · A go/no-go beta recommendation.

## Report Template (fill in, return)
```
## WS-10 QA Report
### Environment: <sim version + real device model + real host OS/shells>
### Results (per item 1–11): <pass/fail + repro + screenshot path>
### Critical failures: <ranked, with owning WS-#>
### #5 real-host blocks: <bash/zsh/fish results; claude dark?>
### #6 reconnect/handoff/scrollback: <each scenario result — the key gate>
### #7 push on real device: <result>  · #8 billing sandbox/Stripe: <result>
### Go/No-Go for TestFlight beta: <recommendation + blockers>
### Deviations/risks:
```
