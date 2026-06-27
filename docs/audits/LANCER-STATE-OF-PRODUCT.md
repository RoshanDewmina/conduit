# Lancer — State of the Product (candid assessment)

*An honest read of where Lancer is right now, so it can be judged on its merits.* 2026-06-23.

---

## TL;DR verdict
Lancer is a **working, differentiated alpha** with its single hardest technical bet already proven, and a real but rough path to a shippable V1. The core promise — *approve your AI coding agents from your locked phone* — **works end-to-end on a real device today**. What stands between it and a confident public launch is **not core capability** but **packaging**: onboarding friction, surface sprawl, a couple of unproven-at-scale claims, two infra/distribution blockers, and one failing contract test on the marquee feature. It is **pitchable now as a demo/alpha**; it is **not yet** a "download it and it just works" product for strangers.

**One-line judgment:** strong thesis, the hard part is done, the last 20% (polish + distribution + trust) is what's left — and that 20% is what users actually judge.

---

## What it is (context for the assessment)
Mission control for AI coding agents (Claude Code, Codex, OpenCode, Kimi) that run on the developer's **own** machines. A resident daemon governs every risky agent action; the phone approves/denies — even with the app closed and locked. Phone steers and approves; it is not a phone IDE. Three layers: iOS app, `lancerd` daemon, and a hosted relay/push backend.

---

## Maturity by capability
Scale: **Proven** (works end-to-end, verified) · **Working** (built + wired, lightly tested) · **Partial** (works with caveats) · **Future** (designed, not in V1).

| Capability | State | Notes / evidence |
|---|---|---|
| Governed approval loop (dispatch → policy → approve → continue) | **Proven** | Verified on simulator + **physical device, app closed, lock-screen approve** (the #1 risk) on 2026-06-23. |
| Lock-screen / app-closed push approval | **Proven (once)** | Passed on a real iPhone after a 5-bug fix. Proven, but not yet hardened across devices/networks. |
| Multi-vendor dispatch + follow-up/continue | **Working** | Implemented for all 4 vendors; per-vendor argv drifts and needs re-verification. |
| Policy engine (allow/ask/deny, autonomy presets) | **Working** | Go engine with 124 passing tests; the backbone of the product. |
| Fleet / hosts (health, status) | **Working** | Real screen with relay + SSH hosts, online/health. |
| Setup-drift detection | **Working** | A genuine differentiator; post-launch moat, lightly exercised. |
| Quota guard (spend caps) | **Working** | Per-provider caps; not stress-tested with real billing. |
| Audit log (hash-chained) | **Working** | Verify/export present. |
| Secrets broker | **Working** | Store/authorize/revoke; on-device keys. |
| Live terminal (block-rendered PTY) | **Working** | Power-user/SSH path; secondary to the approval loop. |
| Apple Watch approvals | **Working** | Present; not the focus. |
| macOS companion (manage daemon) | **Working** | Menu-bar app. |
| Live Activity (lock-screen run status) | **Partial 🟥** | Wired, but a **failing contract test** (timestamp encoding) means lock-screen timestamps may be wrong — needs triage. |
| Performance at scale | **Unproven** | Budgets defined; not measured under large transcripts / many hosts. |
| Reconnect / offline / error recovery | **Partial** | Logic exists; no automated coverage. |
| Onboarding | **Partial / weak** | Functional but value is gated behind an account fork + setup; highest-friction surface. |
| Hosted-cloud execution (run agents in cloud, prepaid credits) | **Future** | Designed, code retained, deliberately out of V1. |
| Scheduled / looping agents | **Future** | Backend exists, no UI. |

---

## Readiness scorecard (judge it on these)
| Dimension | Grade | Reasoning |
|---|---|---|
| **Core functionality** | 🟢 Strong | The hard loop works and is device-proven. |
| **Differentiation** | 🟢 Strong | App-closed governed approvals + runs-on-your-machines + drift detection is a real wedge. |
| **Reliability** | 🟡 Unproven | Proven once on device; no reconnect/scale test coverage. |
| **UX / onboarding** | 🟡 Rough | Clean core screens; onboarding and surface sprawl hurt first impressions. |
| **Quality / tests** | 🟡 Mostly green | iOS 463/464, Go all green — but the 1 failure is on the flagship feature. |
| **Trust / security** | 🟢 Strong on paper | E2E relay, on-device keys, fail-closed, audit. Not independently reviewed. |
| **Distribution / install** | 🔴 Blocked | TestFlight build exists, but the daemon installer + relay naming aren't tester-ready. |
| **Polish / consistency** | 🟡 Good base | Distinctive design system; some density/state-coverage gaps. |

---

## Honest strengths
- **The thesis is right and timely.** Autonomous agents need a governor; "approve from your pocket" is a sharp, ownable position.
- **The riskiest feature already works** on real hardware with the app closed — most competitors stop at notifications.
- **It runs on the user's own machines with their own keys**, end-to-end encrypted — a strong trust story for developers wary of a middleman.
- **A real, opinionated design language** (editorial dark theme) — it looks like a product, not a dashboard.
- **Defensible extras** (setup-drift, quota guard, hash-chained audit) that competitors don't have.

## Honest weaknesses & risks (what to be skeptical about)
1. **"Proven once" ≠ "reliable."** The flagship path passed on one device after fixing five stacked bugs; it has not been hardened across devices, networks, reconnects, or scale.
2. **A failing contract test on the marquee surface** (Live Activity timestamps) — lock-screen run status may be subtly wrong until triaged.
3. **Onboarding is the weakest link** — value is shown only after an account decision and setup; this is exactly where new users churn.
4. **Surface sprawl** — the product is narrower than its code implies; without simplification, it reads as complex.
5. **Distribution isn't tester-ready** — the daemon install one-liner and relay/host naming need to be fixed before strangers can self-serve.
6. **Unmeasured at scale** — performance and reliability under real, busy fleets are unknown.
7. **Depends on vendor CLIs** that drift — multi-vendor support is maintenance-heavy.

---

## Where it stands for pitching
- **Pitch as:** a working alpha with a proven hard part and a clear wedge — ideal for design-partner / early-tester conversations and live demos (the approve-from-lock-screen demo is genuinely compelling).
- **Don't yet pitch as:** a self-serve, rock-solid V1 — install friction and onboarding will undercut a cold "try it yourself."
- **The credible story:** "The hard technical bet is done and proven on-device. We're now hardening reliability, simplifying onboarding, and finishing distribution for a public V1."

## What would move each grade up (shortlist)
- Re-run the live loop across **multiple devices/networks + reconnect** → Reliability 🟡→🟢.
- **Fix the Live Activity test** → removes the one red mark on the flagship feature.
- **Cut onboarding to value-first (3 screens)** and simplify IA (6 roots → 4) → UX 🟡→🟢.
- **Ship a working daemon installer + vanity relay domain** → Distribution 🔴→🟢.
- A **second independent on-device proof** + a small reliability test suite → de-risks the "proven once" caveat.

---

*Basis: full product/UX audit + verified builds/tests + real-app screen walkthrough, this repo, 2026-06-23. Companion docs: `LANCER-PRODUCT-OVERVIEW.md`, the audit reports in `docs/audits/`, and the design brief in `docs/design-handoff/`.*
