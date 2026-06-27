# Lancer — State of the Product (detailed assessment)

*A thorough, evidence-grounded read of where Lancer stands so it can be judged rigorously and pitched honestly.*
Compiled 2026-06-23 from a full product/UX/code audit, verified builds & tests, and a real-app screen walkthrough of this repository. Where a claim rests on evidence, the evidence is named (file, RPC, test, or screenshot).

---

## 0. How to read this
Maturity scale used throughout:
- **Proven** — works end-to-end and was verified running (device/sim/test), not just present in code.
- **Working** — built and wired into the app; lightly tested; no reason to think it's broken.
- **Partial** — works with material caveats or only in part.
- **Scaffolded** — backend/logic exists but no real UI or not reachable.
- **Future** — designed/retained in code but deliberately out of the current (V1) product.

Confidence tags: *(verified)* = I ran it or saw it; *(code)* = read in source; *(reported)* = from project docs/prior runs.

---

## 1. Executive verdict

Lancer is a **working, differentiated alpha**. Its single hardest technical bet — *approve a risky agent action from a locked phone with the app closed* — **is proven on a real device** (2026-06-23). The core loop (dispatch → policy → approve → continue) works end-to-end. A first TestFlight build exists.

What separates it from a confident public V1 is **not core capability** but **packaging and proof**:
- onboarding gates the value behind account setup;
- the live surface is broader than the V1 story (sprawl);
- the flagship lock-screen feature carries **one failing contract test**;
- reliability is **"proven once," not hardened** (no reconnect/scale coverage);
- distribution (daemon installer, relay naming/vanity domain) **isn't tester-ready**.

**Judgment:** the thesis is strong and timely, the hard part is done, and the remaining ~20% (polish, onboarding, reliability proof, distribution) is exactly the part end users judge. **Pitchable now** as a proven-hard-part alpha for design partners and live demos; **not yet** a "strangers self-serve and it just works" product.

---

## 2. Product definition

**What it is.** iOS mission control for AI coding agents (Claude Code, Codex, OpenCode, Kimi) that run on the developer's **own** machines/servers. The phone **steers and approves**; it is explicitly **not** a phone IDE.

**The problem.** Autonomous coding agents force a bad choice: let them run unsupervised (risk: destructive or wrong actions) or babysit the terminal (cost: tied to a desk). Neither scales as agents get more capable and longer-running.

**The wedge.** Insert a governor between the agent and the machine. A resident daemon watches every action; risky ones pause and route to the phone as a one-tap, context-rich approval — deliverable even when the app is closed and the phone is locked.

**Who it's for.** Developers/teams running autonomous or long-running agents who want to supervise remotely — start work, intervene on the dangerous moments, and stay mobile.

**Core value proposition.** *Your coding agents, supervised from your pocket* — approve from afar, watch the work live, enforce policy per host.

---

## 3. Architecture (what it's built on, and why it matters for judging it)

Three layers *(code)*:
1. **iOS app** (`Packages/LancerKit/`, ~21 Swift modules) — the phone client: chat threads, inbox, fleet, settings, terminal, onboarding.
2. **`lancerd`** — a resident Go daemon on each host. Owns the **policy engine**, approval queue, audit log, session indexing, and the adapters that launch/continue each vendor CLI (`dispatch.go`). It is the trust boundary.
3. **`push-backend` + `agent-runner`** — hosted Go control plane. In V1 its job is the **end-to-end-encrypted relay** + **APNs push**. (`agent-runner` and the hosted-execution parts are V2.)

**Transports** *(code)*:
- **V1 = E2E relay.** Phone pairs to the relay; daemon connects host-side; phone ↔ relay ↔ daemon, end-to-end encrypted (relay forwards ciphertext). The phone never holds an SSH session in V1.
- **SSH = legacy/power-user.** Still in code (`DaemonChannel`, `SSHTransport/`); convenient for local testing; not the V1 story.

**Why this matters:** the security/trust story (on-device keys, E2E relay, fail-closed daemon) is a genuine differentiator for a developer audience — but it also means reliability depends on the relay + daemon + APNs chain all holding up, which is the main reliability unknown.

---

## 4. Capability-by-capability assessment (the core of this report)

### 4.1 Governed approval loop — **Proven** *(verified)*
- **What:** agent PreToolUse → daemon policy evaluate → allow/deny auto, or "ask" → queued → phone approve/deny/edit → decision relayed back → agent unblocks. Fail-closed (~120 s timeout).
- **Evidence:** verified on simulator + localhost, and the full **physical-device, app-closed, lock-screen-approve** path PASSED 2026-06-23 (C2) after fixing a 5-bug chain (bundle-id rebrand, relay device-registration, /approval auth, sandbox APNs fallback, foreground re-registration). Policy engine has 124 passing Go tests.
- **Caveat:** proven, but on **one device, one session**. Not yet hardened across devices/networks/reconnects.
- **Judgment:** this is the product's spine and its strongest asset. The demo is genuinely compelling.

### 4.2 Lock-screen / app-closed delivery — **Proven (once)** *(reported, device)*
- Real APNs push with Approve/Reject actions on the lock screen; decision routed without foregrounding the app.
- **Risk:** "passed after fixing five stacked bugs" signals fragility; needs a second independent on-device proof and network-variation testing.

### 4.3 Live Activity (lock-screen run status) — **Partial 🟥** *(verified)*
- Push-driven Live Activity is wired (token registration → push-backend → ActivityKit) so status updates while the app is closed.
- **But:** an iOS unit test **fails** — `LiveActivityContentStateTests.lastUpdateEncodesAsUnixNumber`. Root cause: Swift's default `JSONEncoder` encodes `Date` as seconds-since-2001, not Unix epoch, so the lock-screen timestamp contract with the backend is mismatched. **Unresolved.** This is the single red mark on the flagship surface and should be triaged before relying on Live Activity timing.

### 4.4 Multi-vendor dispatch + continue/follow-up — **Working** *(code)*
- Dispatch and `continue` implemented for all four vendors in `dispatch.go` (`continueArgv`). Durable chat threads (`ChatConversationRepository`), new runId per turn, re-checked against policy.
- **Caveat:** vendor CLI flags drift; the project itself flags "re-verify per vendor before trusting." Maintenance-heavy by nature.

### 4.5 Policy engine & autonomy — **Working** *(code, tests)*
- Allow/ask/deny rules, autonomy presets (Balanced/Permissive/Restrictive), per-host enforcement; **Emergency Stop** halts all running agents (SSH + relay). 124 Go tests pass.
- **UX caveat:** policy is exposed in three places (onboarding preset, Settings→Autonomy, Settings→Policy editor) — conceptually scattered.

### 4.6 Fleet / hosts — **Working** *(verified screen)*
- Machines view: relay + SSH hosts, online/health, agents-on-host, usage, saved hosts. (`real-04-machines.png` shows "Dev VPS · online·healthy", saved hosts list.)
- RPCs: `agent.host.health`, `agent.status`, `agent.agents.installed` *(code)*.

### 4.7 Setup-drift detection — **Working** *(code)* — *differentiator*
- Daemon `drift.go` + `agent.drift.scan`; surfaced as a Fleet stat and a findings view. Catches a host's agent environment silently breaking. Competitors don't have this. Lightly exercised.

### 4.8 Audit log — **Working** *(code)*
- Hash-chained (`audit.go`); `agent.audit.tail/verify/export`. Verify + export present in the app.

### 4.9 Quota guard (spend) — **Working** *(code)*
- Per-provider daily/monthly caps; `agent.quota.status/setCap/updateSpend`. Not stress-tested against real billing.

### 4.10 Secrets broker — **Working** *(code)*
- Agent requests a secret → phone authorizes/revokes; keys stay on device. `agent.secret.*`.

### 4.11 Provider keys — **Working** *(verified screen)*
- Keys go device→provider directly; "Lancer never sees them" (`real-07-settings-providerkeys.png`).

### 4.12 Live terminal (block PTY) — **Working** *(code)*
- OSC-133 block rendering, custom terminal keyboard, snippet palette, port-forward, dictation, tmux (`SessionView.swift`). Power-user/secondary path.

### 4.13 Apple Watch approvals — **Working** *(reported)*
- Approvals on the wrist; not the product focus.

### 4.14 macOS companion — **Working** *(reported)*
- Menu-bar app manages the daemon, pairing QR.

### 4.15 Reliability / reconnect / offline — **Partial** *(code)*
- Reconnect/rearm logic exists; **no automated tests** for background→foreground, network switch, daemon restart (project's own C4 gap).

### 4.16 Performance at scale — **Unproven** *(reported)*
- Budgets defined; list virtualization present; **not measured** under large transcripts or busy fleets.

### 4.17 Onboarding — **Partial / weak** *(code, audited)*
- Production flow: account entry → value hero → pair → policy preset → optional SSH. **Value is shown after** an account fork that introduces ~5 concepts (account, recovery, device mgmt, billing, offline pairing). Real prior-session user hit an ordering gap at the pairing step. This is the highest-friction surface and the biggest first-impression risk.

### 4.18 Hosted-cloud execution — **Future** *(code, retained)*
- Run agents in the cloud on prepaid credits; ~900 LOC of UI retained but unwired. Deliberately out of V1.

### 4.19 Scheduled / looping agents — **Future / Scaffolded** *(code)*
- `agent.schedule.*` and `agent.loop.*` exist in the daemon; **no real UI**. Out of V1.

### 4.20 CI events / git-clone — **Scaffolded** *(code)*
- `agent.ci.recent`, `agent.git.clone` have no app caller. Backend-only.

---

## 5. Feature coverage — backend vs frontend (where the product is thin)
From the backend↔frontend trace *(code)*: **45 daemon RPCs + ~40 backend routes**; **~27 RPCs have a real user-facing trigger**.
- **Backend-only / no UI:** `git.clone`, `ci.recent`, `schedule.*`, `loop.*` (+ `pause`/`resume` exist but have **no button**).
- **Future, retained, unwired:** hosted-cloud execution, worktrees.
- **Takeaway:** the *shipping* product is meaningfully **narrower than the codebase implies**. That's good for focus but means the surface needs trimming so it reads as simple, not half-built.

---

## 6. Screen-by-screen current state *(verified via real-app captures)*
- **Home** — editorial header, a warm "WAITING ON YOU · N conversations blocked" attention card, your machines. Clean, strong. (Bug: demo-seed counters can persist into a real empty state — see Risks.)
- **New Chat** — "Describe the work. Lancer routes it through policy before anything runs." + composer + agent/host picker. Strong.
- **Inbox** — risk-rated approval cards (e.g. `rm -rf ./dist` HIGH RISK, `git push --force` MEDIUM) with Deny/Approve. The system-of-record. Strong.
- **Machines** — host health, agents-on-host, usage/drift, saved hosts. Solid.
- **Settings** — cleanly grouped (Policy & Governance / General) at the top level; the sprawl is in its **depth** (~12 sub-screens).
- **Not yet captured this session** (described from source in the design brief): chat thread/transcript, approval detail, terminal, onboarding steps, most settings sub-screens, machine detail, add-machine, archive, drift, quota, relay files, diff. (Capture checklist provided.)

---

## 7. Quality & test state *(verified this session)*
| Gate | Result |
|---|---|
| LancerKit `swift build` | ✅ |
| iOS app-target build | ✅ 0 errors/warnings |
| macOS `swift test` | ✅ 13/13 (platform-agnostic only) |
| **iOS simulator test suite** | 🟥 **463 / 464 — 1 failure** (Live Activity timestamp contract) |
| Go `go test ./...` ×3 (lancerd/push-backend/agent-runner) | ✅ |
| UI tests | 2 remain; some legacy tab-bar tests quarantined |

**Note:** the project docs' "385 tests green" is stale; the real current iOS count is 464 with one failure. Untested areas (project's own gaps): real remote-host E2E, reconnect/offline as tests, IAP in TestFlight, broad VoiceOver/Dynamic-Type sweep.

---

## 8. Readiness scorecard (graded, with reasoning)
| Dimension | Grade | Reasoning |
|---|---|---|
| Core functionality | 🟢 Strong | The hard loop works and is device-proven. |
| Differentiation | 🟢 Strong | App-closed governed approvals + runs-on-your-machines + drift detection. |
| Architecture | 🟢 Clean | Strict module discipline; sidebar IA; clear trust boundary. |
| Security/trust (on paper) | 🟢 Strong | E2E relay, on-device keys, fail-closed, hash-chained audit. Not externally reviewed. |
| Reliability | 🟡 Unproven | Proven once on device; no reconnect/scale coverage. |
| UX / onboarding | 🟡 Rough | Strong core screens; weak onboarding; surface sprawl. |
| Quality / tests | 🟡 Mostly green | 1 failure on the flagship feature; coverage gaps. |
| Performance at scale | 🟡 Unknown | Not measured. |
| Distribution / install | 🔴 Blocked | TestFlight exists; daemon installer + relay naming not tester-ready. |
| App Store readiness | 🟡 Partial | Build uploaded; IAP/privacy/screenshots not fully closed. |

---

## 9. Risk register (severity × likelihood)
| # | Risk | Sev | Likely | Mitigation |
|---|---|---|---|---|
| R1 | Flagship loop fragile beyond the one proof | High | Med | Re-prove across devices/networks + reconnect; add a reliability suite. |
| R2 | Live Activity timestamp contract bug | Med | High (present) | Fix the Date encoding; re-run the test. |
| R3 | Onboarding churn (value gated behind setup) | High | High | Value-first 3-screen flow; defer account to after pairing. |
| R4 | Distribution not self-serve (installer/relay) | High | High | Ship working `lancerd` installer + vanity relay domain. |
| R5 | Vendor CLI drift breaks dispatch/continue | Med | Med | Per-vendor adapter audit + smoke tests in CI. |
| R6 | Perception of complexity (sprawl) | Med | Med | Trim surface; 6 roots → 4; hide power-user depth. |
| R7 | Demo-seed data leaks into real empty states | Low | Med | Gate seed behind a flag; clean zero-state. |
| R8 | Unmeasured performance at scale | Med | Unknown | Load-test large transcripts/fleets. |
| R9 | Security claims unreviewed | Med | Low | Independent security review before public V1. |

---

## 10. Competitive positioning
- **vs. "agent + notifications":** Lancer's approvals are **blocking, context-rich decisions** that gate the agent — not after-the-fact alerts.
- **vs. cloud agent platforms:** Lancer runs on the **user's own machines with their own keys**, end-to-end encrypted — a trust advantage for developers wary of a middleman (at the cost of more setup).
- **vs. terminal/IDE tools:** Lancer is **mobile supervision**, not another place to write code — complementary, not competing.
- **Moats forming:** setup-drift detection, hash-chained audit, quota guard, app-closed approval UX.

---

## 11. Go-to-market readiness
- **Pitch it as:** a working alpha whose hardest technical bet is proven on-device — ideal for **design partners, early testers, and live demos** (the approve-from-lock-screen demo lands).
- **Don't pitch it as:** a polished self-serve V1 — install friction + onboarding will undercut a cold "try it yourself."
- **Credible narrative:** "The hard part — governed approval from a locked phone — is done and proven on a real device. We're now hardening reliability, simplifying onboarding, and finishing distribution for a public V1."
- **Best live demo:** start an agent → it hits `rm -rf` / `git push --force` → lock the phone → approve from the lock screen → agent continues. That's the whole thesis in 30 seconds.

---

## 12. Path to a confident V1 (prioritized)
1. **Fix the Live Activity timestamp test** (removes the flagship red mark). *Small.*
2. **Re-prove the live loop** across ≥2 devices + networks + reconnect; add a minimal reliability suite. *Medium — biggest credibility unlock.*
3. **Onboarding: value-first, 3 screens**; defer account; make SSH contextual. *Medium — biggest UX unlock.*
4. **Distribution:** working daemon installer + vanity relay domain + clean tester path. *Medium — unblocks self-serve.*
5. **IA simplification:** 6 roots → 4 (fold Inbox into Home); trim settings depth; gate demo-seed data. *Medium.*
6. **App Store close-out:** IAP verified in TestFlight, privacy label, screenshots, security review. *Owner-gated.*

---

## 13. Open questions / unknowns (be honest in the pitch)
- How reliable is the loop across real networks and reconnects? (Unknown — one proof.)
- How does it perform with large transcripts and many hosts? (Unmeasured.)
- Does multi-vendor `continue` hold for each vendor right now? (Needs re-verification.)
- Will the security model survive independent review? (Not yet reviewed.)
- What's the activation funnel through the current onboarding? (Likely the weakest metric.)

---

*Basis: full product/UX/frontend-coverage audit, verified `swift build` / app-target build / `swift test` / `go test` / iOS sim test run, and a real-app screen walkthrough — this repo, branch `rebrand/lancer`, 2026-06-23. Companion docs: `docs/audits/*` (matrix, screen inventory, UX, tests), `docs/design-handoff/application-redesign-brief.md`, and `LANCER-PRODUCT-OVERVIEW.md`.*
