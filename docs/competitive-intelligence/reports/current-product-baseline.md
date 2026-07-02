# Lancer — Current Product Baseline (evidence-grounded)

> Compiled 2026-07-02 for the competitive-intelligence program. This is Phase 1: what Lancer
> actually is today, verified against running code, not aspirational docs. Where a doc and the
> code disagree, this file says so explicitly and defers to code.
>
> **Method:** direct repository inspection (`Read`/`Bash`/`grep` across `Packages/LancerKit/`,
> `daemon/`), cross-checked against `ARCHITECTURE.md` §0.1/§4.1 (updated 2026-06-27),
> `docs/KNOWN_ISSUES.md` (updated 2026-07-02), `docs/PUBLISH_READINESS_CHECKLIST.md` (2026-06-27),
> `docs/validation-cycle-v1.md` (2026-06-24), and `docs/LAUNCH_AUDIT-2026-06-18.md`. Live
> app/daemon runs were **not** re-executed for this pass — the verified build/test evidence in
> those docs (449 Swift tests / 75 suites, Go `go test ./...` green across `lancerd`/`push-backend`/
> `agent-runner`, app-target sim build SUCCEEDED, physical-device APNs-closed loop PASSED
> 2026-06-23) is treated as current, dated evidence rather than re-verified from scratch, per
> the "run the product where practical" instruction — practicality here favored spending the
> research budget on external market evidence, which this repo's own docs do not and cannot cover.

---

## 1. What Lancer is (one paragraph, code-verified)

Lancer is an iOS/iPadOS "mission control" for AI coding agents (Claude Code, Codex, OpenCode,
Kimi) that run on a developer's own machines or servers — not a phone IDE, not a generic SSH
terminal. Three layers: a SwiftUI app (`Packages/LancerKit/`, 20 SPM feature/engine modules), a
resident Go daemon (`daemon/lancerd/`) that evaluates policy/audit/dispatch and survives SSH
drops, and a hosted Go control plane (`daemon/push-backend/`, `daemon/agent-runner/`) that carries
an end-to-end-encrypted blind relay plus APNs. The phone never holds the plaintext session in V1 —
it pairs to the same relay the daemon does; the relay forwards ciphertext it cannot read.

## 2. Current architecture (as built, not as originally speced)

```
┌────────────────────────────┐
│  iOS/iPadOS app             │  Packages/LancerKit/ — 20 SPM modules
│  Sidebar/Command-Home shell │  AppFeature router; NOT a tab bar
└──────────────┬───────────────┘
               │ E2E-encrypted blind relay (primary, V1)   ┆ SSH (legacy/power-user, secondary)
               ▼
┌────────────────────────────┐
│  push-backend (Cloud Run)   │  daemon/push-backend/ — Stripe billing, quotas, orgs,
│  = relay + APNs + billing   │  artifacts, run-logs, dispatch spine, relay pairing
└──────────────┬───────────────┘
               │ same relay, host side
               ▼
┌────────────────────────────┐
│  lancerd (resident daemon)  │  daemon/lancerd/ — policy engine, hash-chained audit,
│  runs on dev's own machine  │  drift detector, dispatch.go (Claude/Codex/OpenCode/Kimi argv)
└──────────────┬───────────────┘
               │ spawns / gates via hooks or a real plugin (OpenCode)
               ▼
     Claude Code · Codex · OpenCode · Kimi (vendor CLIs, unmodified)
```

`agent-runner` (hosted-cloud execution — run agents on Fly/GCP/Lightsail with prepaid credits) is
**deferred to V2, code retained, unwired from V1 navigation** — do not describe it as a live V1
surface.

## 3. Feature inventory — implemented vs. partial vs. deferred vs. dead

Status legend follows `ARCHITECTURE.md` §0.1: ✅ implemented/verified · 🔶 partial/device-gated ·
⏳ planned/not started · deferred (V2, code retained) · deprecated/removed.

| Area | Status | Evidence |
|---|---|---|
| Sidebar/Command-Home shell (not a tab bar) | ✅ | `AppFeature/AppRoot.swift` (`compactRoot`/`regularRoot`), `LancerSidebarView.swift`. `enum Tab` is vestigial — only `.inbox`/`.fleet` reached via `sidebarDetail`. |
| Durable chat threads + follow-up continuation | ✅ | `ChatConversationRepository`, new `runId` per turn, `dispatch.go` `continueArgv` for all 4 vendors |
| Governed approvals: hook→policy→inbox→approve→audit | ✅ | `daemon/lancerd/policy/{evaluate,match,load,simulate}.go`, `InboxFeature/`, fail-closed default `ask`, hold-on-unreachable |
| **Hash-chained audit log** | ✅ | `daemon/lancerd/audit.go:25` `PrevHash` field, chain verification at line 167, JSONL export line 182; iOS side `LancerCore/AuditVerification.swift`, `SettingsFeature/AuditVerifyExportView.swift` |
| Policy presets / matrix / simulator / editor | ✅ | `SettingsFeature/{PolicyHomeView,PolicyMatrixView,PolicySimulatorView,PolicyEditorView,PolicyPresetsView}.swift`, `LancerCore/{NormalizedPolicy,PolicyPreset,PolicySimulation}.swift` |
| Fleet setup-drift detector | ✅ | `daemon/lancerd/drift.go` (+ test), `AppFeature/DriftRemediationView.swift`, `LancerCore/Drift.swift`, `HostHealthStore.swift` |
| Emergency stop (phone-triggered) | 🔶 | Referenced in `AppRoot.swift`, `SettingsView.swift`, Watch connector (`PhoneWatchConnector.swift`, `WatchApprovalTransfer.swift`) — Watch-side stop/deny wired; full fleet-wide kill-switch breadth not independently re-verified this pass |
| E2E-encrypted blind relay (V1 primary transport) | ✅ | Swift: `SSHTransport/E2ERelayClient.swift`, `SessionFeature/E2ERelayBridge.swift`; Go: `daemon/lancerd/{e2e_client,e2e_crypto,e2e_router,relaypair,relay_token}.go`. Relay forwards ciphertext only — confirmed architecturally, not a marketing claim. |
| SSH + unified-PTY block terminal (TOFU, OSC 133/7, alt-screen) | ✅ (code) / deferred (V1 nav) | `SSHTransport/`, `TerminalEngine/`. **2026-06-30 correction:** not wired into V1 IA — "Open terminal" entry points removed from Work Thread/Machines as of 2026-07-01. Code works, is not part of the V1 product story. |
| Multi-vendor dispatch (Claude/Codex/OpenCode/Kimi) incl. continue/resume | ✅ | `daemon/lancerd/dispatch.go` per-vendor argv; **re-verify against each CLI's current flags before trusting** — vendor CLIs drift (per `vendor-cli-adapter-audit` skill) |
| opencode approval gating | ✅ (fixed 2026-07-01/02) | Was **silently non-functional** for an unknown period — the original `hooks.json` mechanism is not real OpenCode config. Replaced with a real `tool.execute.before` plugin (`daemon/lancerd/opencode_plugin_install.go`), re-verified live end-to-end. |
| Push-driven Live Activity (updates while app closed) | ✅ | `daemon/push-backend/liveactivity.go`, `pushType: .token`, redacted alert body (no raw command in APNs payload) |
| Physical-device APNs approval loop, app closed | ✅ **PASSED 2026-06-23** | `docs/test-runs/2026-06-22-full-device-test.md` — C2 gate, the #1 V1 proof point |
| Watch app / widgets | 🔶 | `PhoneWatchConnector` pushes live state (was hardcoded stubs); depth not independently re-audited |
| Biometric gate / app-lock | **removed for V1** (2026-07-01, owner decision) | Approvals commit on tap; app never shows a lock screen — a **regression from the security story** vs. the original spec (§10.2 of `ARCHITECTURE.md` describes biometric gating as a control; current code has removed it for V1). Flag for the security comparison. |
| Standard accounts (Supabase) + device management/revocation | 🔶 | `SettingsFeature/DeviceManagementView.swift`, `GET /v1/devices` + revoke; JWT verification **HS256-only** (no JWKS/RS256 path yet) |
| Hosted-cloud execution UI (`ProviderDetailView` etc.) | deferred V2, retained | 0 refs in V1 nav, compiles, not deleted |
| Tab-bar IA, `ControlView`, `AdaptiveRoot`, standalone Governance root | deprecated/removed | Governance folded into Settings 2026-07-01; superseded by sidebar shell 2026-06-20 |
| Full interactive terminal as a V1 surface | deferred V2 (owner decision 2026-06-30) | Code exists and works; not wired into Home/Work/Machines/Settings IA — Work Thread shows a **read-only** activity log, not a live shell |
| SFTP file browsing, port forwarding, SOCKS preview proxy | deferred V2, code retained | Same 2026-06-30 correction |
| Reverse SSH port forwarding (`tcpip-forward`) | ⚪ known gap | `ARCHITECTURE.md` §3.4 feature matrix — listed as a gap vs. Termius/Blink/Warp, not filled |

## 4. Security model — implemented, with one notable regression

**Real:**
- TOFU host-key confirmation on first SSH connect (`TOFUHostKeyValidator`) — `acceptAnything()`
  never the default in production; auto-trust strictly `#if DEBUG`.
- Keychain storage (`whenUnlockedThisDeviceOnly`, non-synchronizable) for keys/relay credentials.
- Fail-closed policy: daemon-down holds all mutating actions; policy default is `ask`; timeout →
  deny (not allow).
- Hash-chained audit log with chain-verification (`audit.go`), redaction (`AgentKit/Redactor.swift`
  covers PEM keys, Bearer tokens, JWTs).
- No shell interpolation in dispatch — explicit argv, not `sh -c` (verified per `vendor-cli-adapter-audit`
  convention and `docs/KNOWN_ISSUES.md` §2 "exec.Command — explicit argv, no shell").
- Cross-tenant scoping on push-backend (`resolveEntitlementFromBearer` + `resourceVisibleToEntitlement`).
- `APPROVAL_RELAY_SECRET` enforced (401 on unauthenticated relay register/POST) in production.

**Notable regression (flag for the security-comparison report):** Biometric gate / app-lock was
**removed for V1** on 2026-07-01 by owner decision — "approvals commit on tap and the app never
shows a lock screen." `docs/KNOWN_ISSUES.md` §2 still documents `BiometricGate` as degrading open
without a passcode on some devices, which was a **residual concern about a control that has since
been removed entirely for V1**, not fixed. This is a real, current gap between the security
narrative in `ARCHITECTURE.md` §10.2 ("Optional biometric gate at app launch and before key use")
and the shipping V1 app. Any competitive security-posture comparison must use the **current**
posture (no on-device biometric gate on approval-tap), not the architecture doc's aspirational one.

**Known residual security items (not fixed, not blocking):**
- JWT verification is HS256-only; no JWKS/RS256 path if the production Supabase project signs RS256.
- `swift-nio-ssh` dependency is on a community fork (`Wellz26`), tracked but unpatched-CVE risk (LOW, watched).
- `e2eRouter.sendApproval` silently no-ops (with no log line) when the phone isn't paired — found
  2026-06-18 during live testing; a real escalation was dropped this way once. Fail-closed (safe),
  but silently un-diagnosable. Not yet fixed as of 2026-07-02.

## 5. Onboarding / pairing model

QR-based pairing to the E2E relay (`E2ERelayPairingView.swift`), daemon install via
`curl | sh` against a public GCS bucket (`gs://conduit-dist-f1c2466d` — bucket name predates the
Lancer rebrand and is intentionally preserved per the infra-migration decision), manifest-verified
binary download (SHA-256 against an embedded manifest, per `ARCHITECTURE.md` §7.4). Relay
pairing state is stored in iOS **Keychain**, which — unlike UserDefaults or app-container files —
**survives a full app uninstall/reinstall**. This caused a real, found-and-partially-fixed bug
(2026-07-02): stale/dead machines from repeated pairing attempts hit a hardcoded 3-machine cap
with a confusing, contradictory empty-state message across two different screens
(`docs/KNOWN_ISSUES.md`, bottom entry). Fixed: the empty-state copy. **Not fixed:** no in-app
warning that pairing state survives uninstall; no bulk "remove all offline machines" action.

## 6. Strengths (evidence-backed, not aspirational)

1. **The governance wedge is real code, not a pitch deck.** Hash-chained audit
   (`daemon/lancerd/audit.go`), a genuine policy engine with presets/matrix/simulator, and a
   working fleet-drift detector all exist, are wired into the live UI, and pass `go test ./...` /
   `swift test`. This matters because the entire 2026-06-24 strategic pivot (see §8) depends on this
   wedge being real, and it is.
2. **The E2E relay is architecturally sound and differentiated.** Unlike Omnara (admitted no true
   E2EE; plaintext conversations/diffs on their servers per the existing `research/_raw/omnara.md`
   dossier), Lancer's relay is a blind forwarder — the host-side crypto (`e2e_crypto.go`) and
   client-side (`E2ERelayClient.swift`) match on inspection; this is a structural claim, not a
   marketing one.
3. **Multi-vendor dispatch actually spans four CLIs with continue/resume**, not just Claude Code —
   this is the one first-party gap (per `research/_raw/platform-anthropic-openai.md`, both Anthropic
   Remote Control and Codex-in-ChatGPT are single-vendor by construction).
4. **The physical-device, app-closed APNs approval loop is proven**, not simulator-only — a
   meaningfully rarer proof point than most of the competitor set (see §9 below; Omnara's own issue
   tracker shows the equivalent surface breaking in production, `research/_raw/omnara.md` GH #276).
5. **The opencode gating bug-and-fix (2026-07-01/02) is itself evidence of engineering rigor**, not
   just a scar: the team caught that a previously "shipped" gating mechanism was silently inert and
   replaced it with a real extension point, verified live. That's the kind of defect governance-focused
   buyers will ask about directly.

## 7. Weaknesses / gaps (evidence-backed)

1. **Biometric gate removed for V1** — a real regression against the security narrative the whole
   governance pivot depends on selling (§4). Any competitor or reviewer who tests "what stops someone
   who has my unlocked phone" will find: nothing, currently — approvals commit on tap.
2. **Terminal/diff/file depth is explicitly demoted in V1** — Work Thread is a read-only activity
   log, not a live shell; SFTP/port-forward/preview proxy exist in code but are unwired. This is a
   deliberate scope cut (2026-06-30), not a bug, but it means Lancer currently competes on
   governance alone, not on the "steer + review" breadth that Codex-mobile/Copilot-CLI-remote/Cursor
   already ship (see `research/_raw/platform-others.md`).
3. **Emergency stop breadth is not fully re-verified this pass** — Watch-side deny/stop exists;
   whether a true fleet-wide kill switch (stop *every* agent on *every* host) is implemented and
   reachable from the phone UI was not independently confirmed in this baseline (flagged, not
   asserted either way).
4. **App Store readiness is the long pole, not engineering.** Per `docs/PUBLISH_READINESS_CHECKLIST.md`
   §D: App Store Connect record/IAP/privacy label/screenshots are not started (D2); TestFlight is
   uploaded but App Review / DNS / vanity domain remain owner-gated human actions, not code work.
5. **JWT verification is HS256-only** — a real gap if the production identity provider ever signs RS256.
6. **Documentation sprawl**: ~90 markdown docs, several archived-but-still-discoverable point-in-time
   audits. `docs/agent-contract.md` §8 names the canonical set; this baseline follows that pointer.

## 8. The pivot already in motion — and why it matters for this program

As of 2026-06-24, Lancer's own strategic direction already narrowed *before* this competitive-
intelligence program began, based on a prior research pass (`research/_raw/*.md`, dated
2026-06-23, "Researcher: Claude") plus a referenced "verdict memo on the ChatGPT deep-research
report" (cited in `docs/validation-cycle-v1.md` and `docs/LAUNCH_AUDIT-2026-06-18.md`, plan file
`read-this-claude-code-encapsulated-blossom.md` — **this plan file could not be located in the
repository as of this pass; it is either a session-local Claude Code plan artifact never committed,
or was later removed. Treated as a documented gap, not fabricated.**).

The existing conclusion: the broad "mobile control plane for coding agents" category is
commoditized (OpenAI Codex-in-ChatGPT-mobile, GitHub Copilot CLI remote control + Agent HQ,
Anthropic Claude Code Remote Control, Claude Code Auto mode), and a funded, shipping open-source
competitor (**Omnara**, YC S25) already delivers Lancer's original headline pitch. The prior
research concluded Lancer's only defensible ground is the **policy + audit + emergency-stop
governance layer** for agents running across multiple hosts/providers, and set up
`docs/validation-cycle-v1.md` as a design-partner interview gate (10–15 interviews, explicit
CONTINUE/SUNSET thresholds) to test whether that governance pain is real before further
investment. **As of this pass, there is no evidence in the repo that those interviews have been
run or that the validation cycle has returned a signal** — `docs/validation-cycle-v1.md` reads as
a prepared instrument, not a completed study.

This competitive-intelligence program (Phases 2–9 below) independently re-tests the same question
with fresh external evidence, extends the competitor set, adds App/Play Store and business/pricing
analysis the prior pass explicitly flagged as thin, and checks what has changed in the ~9 days
since 2026-06-23 (a market moving fast enough that "recency churn" was called out as a limitation
in the prior pass itself).

## 9. Contradictions between code and docs found this pass

| Doc claim | Code reality | Resolution |
|---|---|---|
| `ARCHITECTURE.md` §10.2 lists "Optional biometric gate at app launch and before key use" as a current control | Removed for V1 on 2026-07-01 (owner decision); approvals commit on tap | §10.2 is now stale — this baseline treats **no biometric gate** as current truth; flagged for `agent-contract.md` §8 doc-hygiene follow-up (out of scope for this program to fix, since we are not modifying production docs beyond this CI system) |
| `ARCHITECTURE.md` §3 "Competitive landscape" (Termius/Blink/Helm/Nimbalyst/Claude iOS/Codex mobile/Code App/Termux) | Written before the 2026-06-24 pivot; does not mention Omnara, GitHub Agent HQ, Copilot CLI remote control, or the first-party Remote Control/Codex-mobile features that the 2026-06-24 pivot explicitly named as the reason for narrowing | §3 is stale legacy competitive framing. This program's `03-direct-competitors.md` and `04-first-party-platform-threats.md` supersede it. Recommend (not executed, out of scope) that `ARCHITECTURE.md` §3 be rewritten or pointed at this program's reports. |
| `docs/validation-cycle-v1.md` frames itself as the active decision gate | No evidence of interviews run or a recorded signal | Treated as **unresolved** — this program's verdict (see `11-product-strategy.md`) is offered as an independent, evidence-based second opinion, not a substitute for owner-run customer interviews, which remain the highest-value next step regardless of this program's output. |
| Plan file `read-this-claude-code-encapsulated-blossom.md` referenced as the source of the pivot | Not found in repo | Documented gap — see §8. |

---

*Next: `docs/competitive-intelligence/reports/2026-07-02/01-current-product-and-codebase.md`
restates this baseline for the dated report set; this file remains the canonical, continuously-
updatable baseline (re-run this Phase 1 pass, don't hand-edit both).*
