# 00 — Executive summary

> WWDC26 / Xcode 27 opportunity audit for Lancer. Compiled 2026-07-02 from: the July 2
> relay/Siri/Live-Activity session report, five parallel read-only Codex subagents (Device Hub,
> product architecture, security, App Intents/Siri, Live Activities/WidgetKit), five parallel
> Apple-research agents (App Intents/Siri/Schemas, Live Activities/ActivityKit/WidgetKit,
> Foundation Models/Core AI, App Attest/security, MetricKit/StateReporting/SwiftData/Xcode-27
> tooling), direct code inspection, and local Xcode 27.0/`devicectl` verification. Full detail and
> citations are in files `01`–`10` of this directory.

## Verdict

Lancer already has real, working relay transport, governance (policy/audit/blast-radius), Siri
shortcuts, Live Activity/Dynamic Island UI, WidgetKit, and Watch code — this is not a codebase
that needs new features bolted onto empty stubs. But several surfaces are **partial or
misleading**, and the single biggest gap is not a missing WWDC26 API adoption — it's that
approvals aren't cryptographically bound to what the user actually saw, and the no-client fallback
fails open. **The correct first move is hardening the approval trust boundary, then fixing the
Live Activity lifecycle to match what the docs already claim, then adopting entity-backed Siri
surfaces — not adding more Siri commands.** This mirrors the plan's own stated intent and this
audit independently confirms it holds up against the evidence.

## Five highest-value opportunities

1. **Approval content-hash binding** (`07`, `08` #1) — the single largest confirmed security gap.
   Approvals carry no `commandHash`/`diffHash`/`toolInputHash`; a stale or substituted command
   could theoretically execute under a tap that approved something else. Pure protocol work, no
   Apple API dependency, no OS-version gate — buildable today.
2. **Fix the Live Activity lifecycle for app-closed relay use** (`04`, `08` #4–#7) — `AppRoot.swift`
   ends every Live Activity on background, directly contradicting `ARCHITECTURE.md`'s own claim
   of push-driven updates while closed. This is the biggest doc/code mismatch found in the audit,
   and the fix is well-understood (keep the `Activity` reference, drive updates via push token).
3. **Risk-tiered fail-closed no-client policy** (`07`, `08` #2) — the current 8-second
   auto-approve-when-unreachable is a textbook fail-open anti-pattern for an agent executing
   commands on the user's behalf. Fixable by reusing the blast-radius classification Lancer
   already built for Governance.
4. **`AppEntity`/`AppIntentsTesting` adoption** (`03`, `08` #8–#10) — zero production `AppEntity`
   usage today, and the exact bug class that shipped twice in production (registration gap,
   runtime crash) has zero regression coverage. `AppIntentsTesting` runs real execution against
   the compiled app, not mocks — it would have caught both prior bugs.
5. **Approval Copilot, evidence-retrieval-first** (`06`, `08` #13) — Foundation Models' `Tool`
   protocol (local evidence retrieval) and `@Generable` (typed, machine-readable risk verdicts)
   are production-ready today and map cleanly onto Lancer's existing deterministic-policy-engine
   architecture: the AI is structurally incapable of deciding anything, only advising.

## Five major risks or blockers

1. **Approvals are not hash-bound to exact content** (see above) — the largest security concern in
   the codebase, independent of any WWDC26 adoption question.
2. **The no-client fail-open path** — same root issue as #1, different failure mode.
3. **Deployment-target drift**: docs claim iOS 27, `project.yml`/`Package.swift` say 26.0
   (`02`). This blocks `AppIntentsTesting` and Core Spotlight semantic indexing specifically —
   both are hard-gated to iOS 27.0 — and is a five-minute fix once decided, but it IS a decision,
   not just a bug (cuts off iOS 26 users).
4. **WWDC26 beta/API risk**: several of the most interesting new APIs (`Attachment` image input,
   `DynamicProfile`, third-party model routing, `IndexedEntityQuery`) are iOS-27.0-gated or, in
   the third-party-routing case, not shippable at all yet (conforming packages don't exist).
   Confidence on exact payload shapes for ActivityKit push (`04`) is medium, not high — Apple's own
   doc pages didn't render via WebFetch this pass and should be re-verified via direct browser
   fetch before hard-coding into `push-backend`.
5. **The BiometricGate tension** (`07`, `10` #1): the strongest technical answer to gating
   high-risk approvals (`IntentAuthenticationPolicy`, a system-owned Face ID prompt) directly
   reverses a deliberate owner decision made one day before this audit. This audit does not
   implement it and flags it as an explicit owner decision, not a silent recommendation.

## Recommended product direction

Lead with the trust-boundary hardening (items #1–#3 above) since none of it requires any OS
version decision and all of it is real, shippable work this week. Follow with the Live Activity
lifecycle fix, since it's the biggest gap between documented and actual behavior. Then the
App Intents/entity work, gated on resolving the deployment-target question. Treat the Approval
Copilot and semantic search as genuine differentiators worth prototyping, but not before the
trust boundary is solid — an AI explaining a request that isn't provably bound to what executes is
explaining the wrong thing.

## What should be built first

**Approval content-hash binding** (`09`'s Phase 1, first item). It's the highest-value,
lowest-risk, zero-Apple-API-dependency fix in this entire report, and every other security/AI
recommendation in this audit is weaker without it — the Approval Copilot's risk explanation and
the E2E replay-resistance work both compose naturally with the same content-hash envelope once it
exists.

## What should be built first as cleanup (not a feature)

**Resolve the iOS 26.0/27.0 deployment-target drift** (`02`, `09`'s Immediate Fixes). It's cheap,
it's currently a real doc/code contradiction that undermines the "no `#available` gating needed"
claim in `docs/agent-contract.md`, and it's the actual blocker for two of the five highest-value
opportunities above (`AppIntentsTesting`, semantic search) — not a nice-to-have, a prerequisite.

## Report files

- `01-apple-research.md` — official Apple source matrix across all five research domains
- `02-current-codebase-state.md` — implementation matrix, deployment-target drift, dead-code notes
- `03-app-intents-and-siri.md` — entity model, Execution Targets finding, AppIntentsTesting plan
- `04-live-activities-and-dynamic-island.md` — lifecycle gaps, risk-safe states, push-to-start
- `05-device-hub-testing-plan.md` — verified `devicectl` commands, full test matrix
- `06-ai-and-approval-copilot.md` — Foundation Models feasibility, proposed architecture
- `07-security-and-trust.md` — App Attest, hash-binding, replay resistance, BiometricGate tension
- `08-feature-opportunity-ranking.md` — 25-item ranked table with value/effort/risk/dependency
- `09-recommended-roadmap.md` — phased roadmap with files, tests, and complexity per item
- `10-open-questions.md` — six genuinely non-discoverable product/business/owner-decision questions
