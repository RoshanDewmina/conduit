# C6 — Semgrep triage + security-review closure (2026-07-15)

Scanner: `semgrep scan --config auto daemon/ Packages/LancerKit/Sources/` (ERROR+WARNING).
**14 findings, 0 actionable vulnerabilities.** Every result is a false-positive-by-design for
this codebase or an accepted deployment fact, verified at `file:line` below.

## Findings

| Sev | Rule | Site | Verdict |
|---|---|---|---|
| ERROR | dangerous-exec-command | agent-runner/main.go:51, claude_auth.go:96, dispatch.go:616, git.go:73, health.go:153, tmux_session.go:34/44/62, process_provider.go:20 | **BENIGN** — every site is `exec.Command(bin, args...)` with an explicit argv slice; none builds a `sh -c` string or interpolates untrusted input into a shell. This is precisely the `vendor-cli-adapter` discipline AGENTS.md mandates ("never `sh -c` an interpolated prompt; build explicit argv"). dispatch.go:616 is commented `// explicit argv, no shell`; git.go:73 `// explicit argv — no shell interpolation`. |
| ERROR | dangerous-syscall-exec | shim.go:117 | **BENIGN** — `syscall.Exec(real, args, env)` with an argv array is the shim's entire purpose (hand off to the real vendor binary); no shell, no string interpolation. |
| WARNING | ifs-tampering | install.sh:194, :201 | **BENIGN** — textbook safe idiom: `OLD_IFS="$IFS"; IFS=':'` to split `$PATH`, then `IFS="$OLD_IFS"` restores it three lines later. semgrep flags any `IFS=` assignment. |
| WARNING | open-redirect | billing.go:310 | **BENIGN** — redirect target is a fixed `lancer://billing/complete` scheme with `url.QueryEscape(sessionID)` appended; not an attacker-controlled absolute URL. |
| WARNING | use-tls | main.go:179 | **ACCEPTED** — `http.ListenAndServe` without TLS; push-backend runs behind Fly.io TLS termination (edge terminates HTTPS, forwards plaintext on the internal port). Documented deployment fact, not a plaintext-on-the-wire exposure. |

## Security-review status
`docs/SECURITY-REVIEW.md` is the historical WS-8 key-import review (2026-05-31): 0 critical,
0 high, 2 medium (both fixed with regression tests at review time), 7 low. Its low findings
are UX-privacy hardening items (privacySensitive snapshots, biometric lockout fallback) that
are **moot or superseded**: Face ID/biometric gating was removed from the app entirely
(2026-07-07, permanent — see AGENTS.md), which retires LOW-2 (BiometricGate) and the
biometric parts of the review. Current security source of truth is
`docs/legal/SECURITY_ARCHITECTURE.md` + `docs/KNOWN_ISSUES.md`.

**C6 verdict:** no open code-level security actions from the scanner. The remaining launch
security work is operational, not code: the push-backend App Attest / APPROVAL_RELAY_SECRET
env enforcement (already fail-closed in `relay_security.go`, tested) and the physical-device
approval-loop re-proof (C2), both tracked in the publish checklist.
