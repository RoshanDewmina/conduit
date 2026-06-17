# Conduit — Production Readiness Plan (autonomous loop)

> **For the Cursor goal-loop agent.** Run this to take Conduit from its current state to **App-Store-submittable and ready for real users**. Work autonomously, in a loop, across multiple agents, testing at every stage. A human (the owner) is asleep and will review in the morning. **Optimize for a safe, verifiable, reviewable result — not for claiming "done."**

---

## 0. READ THIS FIRST — how to work (non-negotiable)

1. **Study before building.** Read the codebase, the docs, the research, and the competitors (§2). Don't guess APIs — use the MCP servers (§3).
2. **Never commit to `master`.** One git worktree + branch per workstream (`agent/prod-<area>`). Leave branches unmerged for the owner to promote. The owner merges to `master`, not you.
3. **Green-before / green-after, every step.** Baseline then re-run: `cd Packages/ConduitKit && swift build && swift test` (327 tests today), `cd daemon/conduitd && go build ./... && go test ./...`, `cd daemon/push-backend && go test ./...`, `xcodegen generate`. **Zero new Swift 6 concurrency warnings.** Record baseline-vs-final per stage.
4. **Test at every stage** (§ each workstream's "Gate"). A feature isn't done without a passing test or a documented manual verification (simulator screenshot via XcodeBuildMCP).
5. **Never fake.** No fabricated entitlements, test output, screenshots, App Store metadata, usage numbers, or "submitted to App Store" claims. A blocked-but-documented task is a success; a faked one is a failure.
6. **Credentials (§4):** look in the owner's shell env / `~/.zshrc` / Keychain. If a required credential is present, use it (never print or commit it). If absent, **PAUSE that workstream, document exactly what's needed, and continue the others.**
7. **Stop-and-decide points (§6):** at each, write the decision + rationale to the report and either proceed with the safe default or pause if it needs the owner.
8. **Multi-agent:** fan out independent workstreams (§5 has the dependency graph). Use one agent per workstream; sub-split large ones. Coordinate shared files (e.g. `server.go`, `project.yml`) so two agents never edit the same file at once.
9. **Write a running report** to `~/Downloads/conduit-production-report-<date>.md`: per stage — branch, what changed, baseline-vs-final tests, blockers, `TODO(owner)`, decisions made, and the exact manual steps the owner must do. Update it as you go so a crash leaves a trail.

### What "production ready" means here (and its honest limits)
**You CAN get to:** all code/tests/config/assets/docs production-grade; the app archiving cleanly; the command-center features wired into real navigation (not just the debug gallery); backend deployable; security review closed; App Store metadata + screenshots prepared; live validation done **if** credentials exist.
**You CANNOT (and must NOT fake):** the final App Store Connect *submission*, TestFlight upload with real distribution signing, production APNs cert creation, live SSH-host E2E, DNS changes, or creating paid accounts — unless the matching credential/automation is present in the owner's env. For each, get to **"one human action away"** and document that action. Getting there *is* success.

---

## 1. WHERE WE ARE NOW (verified current state)

**Branch reality:** `master` carries the command-center work (resident daemon, policy engine + audit + blast-radius, cross-vendor usage, opencode, WS-B2 dispatch/schedule) and is pushed to origin. `agent/ws-b2-prod` (unmerged) adds ssh-host bridge-dispatch + live-spend budget. Tests: **Swift 327/51 suites green; Go conduitd + policy green.**

**Already done (don't redo):**
- Core SSH/terminal/blocks/reconnect/keys/persistence (see `docs/_archive/remaining-work.md`).
- Approval loop: structured `tool_use`, policy engine (deny→ask→allow, fail-closed default=ask), audit log, allow-always, edit-before-run.
- Cross-vendor: claude/codex/opencode hooks + `agent.status` usage (honest, omits when absent).
- Proactive dispatch/schedule (policy + budget gated).
- Ship-gate partials: `project.yml` uses full `Conduit.entitlements` (push+CloudKit); `DEVELOPMENT_TEAM=39HM2X8GS6`; `ITSAppUsesNonExemptEncryption=false`; `UIBackgroundModes=[fetch, remote-notification]`.
- Strategy/research docs: `docs/{PRODUCT_RESEARCH,_archive/APP_AUDIT,ROADMAP,UX_OPPORTUNITIES,SECURITY-REVIEW}.md`; `~/Downloads/conduit-*research*.md`, `conduit-execution-briefing-2026-06-04.md` (authority doc — §2.7 has the verified market reality + wedge).

**Known gaps / risks to resolve (this plan):**
- **Build env:** the Conduit scheme embeds a **watchOS app**; **watchOS 26.5 runtime may be missing** → full-scheme build fails. Fix the runtime or descope watch for CI (see WS-1).
- **Feature wiring:** policy editor, audit "while-you-were-away" feed, usage dashboard, dispatch composer exist but several are only reachable via the **debug gallery** (`CONDUIT_GALLERY` routes), not the real app navigation. Wire them into real surfaces.
- **APNs loop / token routing** end-to-end on a real device (needs paid acct + device).
- **Backend deploy:** `daemon/push-backend` (APNs + Stripe + control plane) to production (Cloud Run); live Stripe keys; production push cert.
- **Live validation:** real SSH host running claude/codex/opencode (owner blocker).
- **App Store:** metadata/screenshots finalized, privacy policy + nutrition label, archive + upload.

---

## 2. STUDY (do this first, in parallel)
- **Codebase:** `CLAUDE.md`, `ARCHITECTURE.md`, `docs/agent-contract.md`, `docs/block-terminal-implementation.md`, `docs/_archive/remaining-work.md`, `docs/ship-gate-owner-steps.md`, `docs/validation-playbook.md`, `docs/SECURITY-REVIEW.md`, `docs/ship-gate-owner-steps.md`, `docs/BUILD_PLAN_COMMAND_CENTER.md`.
- **Research + wedge:** `~/Downloads/conduit-execution-briefing-2026-06-04.md` (§2.7 = verified market reality + the wedge), `conduit-deep-market-research-2026-06-04.md`, `deep-research-report.md`, `docs/PRODUCT_RESEARCH.md`. **Our wedge:** the only cockpit where agents run *unattended, safely* — under a policy you control, on infra you own, across every vendor. Every UX decision should reinforce reliability + the autonomy/security story.
- **Competitors (for parity + polish bar):** READMEs in `github_readmes/` (Happy, Omnara, CC Pocket, cmux, Paseo, …). For deeper reference, clone **opencode** (we integrate it; need its hook/SSE API) and **Happy** (MIT; best E2E + push-on-permission reference) into `~/conduit-refs/` (outside the repo, never commit). Do NOT copy AGPL code (cmux, CloudCLI) — ideas only.

---

## 3. MCP SERVERS — prefer these over raw shell
- **XcodeBuildMCP** (`mcp__XcodeBuildMCP__*`): build/test/run the app target, simulator lifecycle, install/launch with `env` (gallery routes), screenshots, coverage, **device build/install + LLDB** (for the real-device APNs test if a device is attached). First call `session_show_defaults` once; set scheme=`Conduit`, a simulator that has its runtime installed.
- **xcode** (`mcp__xcode__*`, needs Xcode open): live diagnostics (`XcodeListNavigatorIssues`), `RunSomeTests`, SwiftUI `RenderPreview`.
- **apple-docs** (`mcp__apple-docs__*`): App Store review guidelines, entitlements, StoreKit, APNs, privacy nutrition labels, Live Activities — **verify before guessing**.
- **context7** (`mcp__context7__*`): third-party SDK docs (Citadel/SSH, swift-crypto, GRDB, Stripe).
- **ios-simulator** (`mcp__ios-simulator__*`): UI automation by accessibility tree (`ui_describe_all`/`ui_tap`/`ui_type`) — use to *drive* real flows (onboarding, approve a card) and assert on-screen state, not just eyeball a PNG.

---

## 4. CREDENTIALS — discover, use safely, or pause
Check (in order) the process env, `~/.zshrc` / `~/.zprofile` / `~/.config`, and Keychain (`security find-generic-password`). Likely names: `APPLE_ID`, `APP_STORE_CONNECT_KEY_ID`/`_ISSUER_ID`/`_KEY` (App Store Connect API `.p8`), `MATCH_*`/fastlane, `STRIPE_SECRET_KEY`/`STRIPE_WEBHOOK_SECRET`, `GCP_*`/`GOOGLE_APPLICATION_CREDENTIALS`, push/APNs `.p8` (`APNS_KEY_ID`/`APNS_TEAM_ID`), `CONDUIT_TEST_HOST`/`_USER`/`_PW` (live host), `conduit-localhost-ssh` Keychain item (local sshd). **Rules:** never print, log, echo, or commit a secret; never put one in a file the repo tracks; if a workstream needs a missing credential, mark it `PAUSED(owner: needs X)` and move on. `fastlane` (`fastlane/`) already exists — prefer it for signing/upload if its creds are present.

---

## 5. ROADMAP — phases, workstreams, gates (multi-agent)

Run phases in order; within a phase, fan out the workstreams in parallel. **Gate = must pass before the phase counts as done.**

### PHASE 1 — Green build everywhere (foundation; do first, mostly serial)
- **WS-1 Build/CI health:** resolve the watchOS runtime (try `xcodebuild -downloadPlatform watchOS`; if unavailable, add a CI scheme/config that builds the iOS app without the embedded watch app, and document it — don't delete the watch target). Get `build_sim` (app target) green; `xcodegen generate` clean; full Swift + Go suites green. Wire a single `scripts/ci.sh` that runs all of it.
- **Gate:** app target builds for simulator; all suites green; one command reproduces it.

### PHASE 2 — Merge-ready integration + feature wiring (parallel)
- **WS-2 Promote `agent/ws-b2-prod`** onto an integration branch off `master`; resolve any drift; re-run all tests.
- **WS-3 Wire features into real navigation:** policy editor, "while you were away" audit feed, cross-vendor usage dashboard, dispatch/schedule composer — reachable from real app surfaces (Settings, Inbox, Agents), not only `CONDUIT_GALLERY`. Drive each with `ios-simulator` UI automation; screenshot proof.
- **WS-4 Empty/error/loading states & a11y:** every new surface has empty/loading/error states, Dynamic Type, VoiceOver labels, light+dark. (Reliability is the wedge — polish it.)
- **Gate:** each feature reachable + demonstrated via UI automation + screenshot; no dead-end states; tests green.

### PHASE 3 — Reliability & notifications (the differentiator)
- **WS-5 APNs loop end-to-end:** close conduitd→push-backend→APNs→device; fix token routing; contextful "waiting vs done" notifications; one-tap approve from lock screen + Watch. Unit/integration test with mocked APNs; real-device test only if a device + push cert exist (else `PAUSED`).
- **WS-6 Reconnect/session-loss hardening:** prove "never lose a session" — background, network switch, daemon restart → queue drains, transcript restores. Tests with the local-sshd fixture.
- **Gate:** push path tested (mock ok); reliability scenarios pass in tests; real-device push documented if blocked.

### PHASE 4 — Security & privacy (App Store + trust)
- **WS-7 Security review closure:** work through `docs/SECURITY-REVIEW.md`; run the `semgrep` MCP scan; ensure secrets never logged, audit redaction holds, TOFU prompt intact in prod paths, fail-closed autonomy verified. Prefer vetted libs over hand-rolled crypto.
- **WS-8 Privacy & compliance:** privacy policy + App Store privacy nutrition label (use apple-docs), data-collection audit, ATS no-arbitrary-loads confirmed, export-compliance correct.
- **Gate:** semgrep clean (or triaged), no secret leakage, privacy doc + label drafted, security posture written to the report.

### PHASE 5 — Backend production (parallel with 3–4 where creds allow)
- **WS-9 push-backend + control plane to prod:** deploy to Cloud Run (use `docs/cloud-run-production-cutover.md` + `push-backend-deploy-env.md`); live Stripe keys + webhook; production push cert; health checks. **Creds-gated** — if absent, prepare manifests + scripts and `PAUSED(owner)`.
- **Gate:** staging deploy verified, or fully prepared + documented if creds missing.

### PHASE 6 — App Store packaging
- **WS-10 Metadata & assets:** finalize `docs/app-store-metadata.md` + screenshots (generate via simulator across required sizes), app icon check, what's-new, keywords aligned to the wedge.
- **WS-11 Archive & signing:** Release archive builds; `fastlane` lane to build/upload to TestFlight **if** App Store Connect creds exist (else produce the signed archive + document the upload step). Never invent provisioning/certs.
- **Gate:** Release archive succeeds; metadata complete; TestFlight upload done OR archive + exact upload steps documented.

### PHASE 7 — Live validation & sign-off
- **WS-12 E2E on a real host (creds-gated):** run `docs/validation-playbook.md` TC-1..TC-7 against `CONDUIT_TEST_*` host (or local sshd fixture for what's possible); golden path hook→policy→inbox→approve→audit; dispatch a real agent; verify fail-closed + budget. If no live host, run the local-sshd subset and `PAUSED(owner)` the rest.
- **WS-13 Final report + go/no-go:** consolidate; list every `TODO(owner)` with the exact action; give a crisp production go/no-go with evidence.

---

## 6. STOP-AND-DECIDE POINTS (write the decision to the report)
1. **watchOS runtime unavailable** → build iOS app without the watch app for CI (document), don't delete the target. Proceed.
2. **A credential is missing** → `PAUSED(owner: needs X)`, continue other streams. Never fake.
3. **A feature needs a live host to verify** → do the local-sshd subset, document the live step. Proceed.
4. **A change would touch `master` or rewrite pushed history** → never; branch instead.
5. **A security finding is high-severity** → stop that stream, document, surface at top of report.
6. **An App Store guideline risk** (e.g. remote code execution framing, encryption) → check apple-docs, document the mitigation/decision.
7. **Ambiguous product/UX call** → pick the option that best serves the wedge (reliability + autonomy/security), document it, proceed.

## 7. VERIFICATION SUMMARY (run continuously)
`scripts/ci.sh` = `xcodegen generate` + app `build_sim` + `swift test` + `go test ./...` (conduitd, policy, push-backend, agent-runner) + `semgrep` scan. Plus per-feature `ios-simulator` UI-automation screenshots. Final ≥ baseline, zero new concurrency warnings, no secrets in diffs.

## 8. DEFINITION OF DONE (what the owner should wake up to)
- An **integration branch** (off `master`, unmerged) with all green workstreams, discrete commits.
- `scripts/ci.sh` green; Release archive builds; features wired + screenshotted.
- Backend deployed-or-prepared; security + privacy closed; metadata + assets ready.
- A complete `~/Downloads/conduit-production-report-<date>.md`: done-vs-blocked, every `TODO(owner)` with its exact one-action step (App Store submit, DNS, live host, any missing cred), decisions log, and a go/no-go.
- **Nothing faked; `master` untouched; no secrets committed.**
