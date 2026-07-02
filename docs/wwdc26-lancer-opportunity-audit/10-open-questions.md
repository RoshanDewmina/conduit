# 10 — Open questions

> Only questions that cannot be answered from the codebase, Apple documentation, existing product
> documents, running the app, or Device Hub testing. Everything discoverable was resolved during
> this audit and is stated as fact in `01`–`09`, not repeated here as a question.

## 1. ~~Should high/critical-risk approvals get a narrow biometric gate?~~ — RESOLVED 2026-07-02

**Owner decision: no.** No Face ID/biometric gate on approvals for V1, full stop — fast
tap-to-approve from anywhere, including the Lock Screen, is a deliberate product choice, not an
oversight. `IntentAuthenticationPolicy` is not on the V1 roadmap. `BiometricGate.swift` stays
unchanged in the tree (it still gates the legacy SSH key-unlock path, which is V2 scope and
doesn't execute for V1). See `07-security-and-trust.md`'s "BiometricGate question" section and
`08-feature-opportunity-ranking.md` item #17.

## 2. Is there a real App Schemas domain fit for Lancer, or should that avenue be closed permanently?

Apple's App Schemas are a fixed, Apple-defined set of domains (Messages, Contacts, Documents, and
similar consumer-app-shaped categories — confirmed via the Messages domain's full enumeration in
the SDK, `03-app-intents-and-siri.md`). None of them obviously match "coding agent run/approval
activity." This audit found no fit and recommends **Reject for now**
(`08-feature-opportunity-ranking.md` #11), but whether Apple might add a more fitting domain in a
future cycle, or whether the product should actively lobby/apply for one (Apple does take schema
domain requests through developer feedback channels, per general knowledge, not independently
verified this pass), is a business/relationship question outside this audit's scope.

## 3. What is Lancer's actual App Review risk tolerance for an AI-advisory security feature?

`06-ai-and-approval-copilot.md` found no Apple guidance — and no general precedent this audit
could independently verify — for the specific scenario of an AI giving security-adjacent
recommendations inside a human-approval flow, even when explicitly advisory-only. This audit
cannot determine from documentation alone whether App Review would flag an "AI risk explanation"
feature for extra scrutiny, require specific disclosure copy, or treat it identically to any other
AI-assisted feature. This needs either a direct App Review precedent search (outside what a
documentation/SDK audit can determine) or a test submission.

## 4. Does the owner want to commit to the iOS 27.0 deployment-target raise now, or defer it?

This is technically a simple fix (`08-feature-opportunity-ranking.md` #16) and this audit
recommends doing it — but raising the deployment target has a real product-facing consequence
(cuts off users on iOS 26) that only the owner can weigh against the value of unlocking
`AppIntentsTesting` and Core Spotlight semantic indexing. This audit surfaces the tradeoff
(`02-current-codebase-state.md`'s deployment-target section) but does not have install-base data
or a target-user-OS-version distribution to make the call.

## 5. Is a custom on-device risk classifier (Core AI/MLX) ever worth pursuing over the simpler prompted-LLM Approval Copilot?

`06-ai-and-approval-copilot.md` and `08` both recommend starting with a prompted
`SystemLanguageModel`/`PrivateCloudComputeLanguageModel` approach and explicitly reject Core AI/MLX
custom-model training for now. Whether that changes depends on real-world evaluation results (does
the prompted approach's accuracy/latency prove insufficient?) that don't exist yet — this is a
"revisit after building #13 and measuring" question, not something resolvable by more research
today.

## 6. What is the actual quota/cost ceiling for Private Cloud Compute usage at Lancer's expected approval volume?

`06-ai-and-approval-copilot.md` flags that PCC has a hidden capacity constraint (free tier capped
low, higher for iCloud+ subscribers) that a review-gate feature cannot afford to silently degrade
under load. This audit could not find Apple-published exact numbers, and even if it had, Lancer's
actual expected approval volume per user per day is a product-usage question this audit has no
data to answer. Needs either a direct Apple developer-relations conversation or empirical
measurement after a prototype ships.
