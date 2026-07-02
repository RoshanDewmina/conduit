# 06 — AI and Approval Copilot

> Research method: local SDK ground-truth grep of `FoundationModels.framework`'s
> `.swiftinterface` on the installed iOS 27.0 SDK (Xcode 27.0, build 27A5194q), cross-checked
> against WWDC26 sessions 241 ("Foundation Models"), 324/326 ("Core AI"), and 339 (third-party
> model routing), plus current App Store Review Guideline text. The `apple-docs` MCP's WWDC index
> only covers through 2025, so 2026-specific claims below come from the SDK interface file (most
> trustworthy — it's the actual shipped API) and WebFetch/WebSearch of developer.apple.com,
> clearly distinguished by confidence level in the table.

## The non-negotiable boundary

```text
Agent request
     ├── Deterministic policy engine → allow, block, or require approval   (authoritative)
     └── Independent AI reviewer     → explanation and supporting evidence  (advisory only)
```

Nothing in the `Tool`/`Generable`/`LanguageModel` API surface grants a Foundation Models session
any ability to *act* on the user's behalf — it can only be asked a question and answer in a typed
schema. This maps cleanly onto Lancer's existing architecture: `daemon/lancerd/policy/evaluate.go`
remains the sole authority; a Copilot session would sit entirely on the phone/client side,
consuming the same approval payload the human sees, and its output would be a **typed
`RiskVerdict` value displayed alongside** the approve/deny buttons — never wired to auto-decide
anything. This is a strictly additive feature with zero blast radius on the existing approval
path if built correctly.

## API / capability table

| API / capability | Min OS + Xcode | Beta? | Entitlements | Restrictions | Background limits | Privacy / App Review | Applicability | Source | Confidence |
|---|---|---|---|---|---|---|---|---|---|
| `SystemLanguageModel` (on-device LLM) | iOS 26.0+ baseline; present in iOS 27 SDK | N | None found (no `NS*UsageDescription` Info.plist key) | Requires Apple-Intelligence-eligible device + feature enabled by user; language must be in `supportedLanguages`/`supportsLocale(_:)` | Foreground-oriented, no special always-on mode | On-device, private by default | Default/offline engine for the Copilot | SDK L43-88 | High |
| `SystemLanguageModel.Availability`/`UnavailableReason` | iOS 26.0+ | N | — | Exact cases: **`.deviceNotEligible`, `.appleIntelligenceNotEnabled`, `.modelNotReady`** — no explicit region/language case; those surface via `appleIntelligenceNotEnabled`/`supportsLocale()` | — | App must branch on all 3 states | Defines the Copilot's required fallback UX contract | SDK L264-283 | High |
| `PrivateCloudComputeLanguageModel` | New capability emphasis in iOS 27 (Availability/Quota extensions `@available(iOS 27.0...)`) | N (shipped; watchOS specifically requires PCC) | None to call; Apple-side quota billing | 32K token context, `.light`/`.deep` reasoning levels, **quota-limited** (free tier capped low, higher for iCloud+) | Same "verifiably private, not stored" PCC model | No prompt storage; independently verifiable | Higher-quality tier for ambiguous/destructive-looking requests | SDK L45-138; WWDC26 s241 | Med-High |
| Third-party model routing (`LanguageModel` protocol, external Anthropic/Google conformers) | iOS 27.0+ protocol; conforming packages **not yet shipped** | **Y — treat as unavailable today** | 3rd-party auth (token provider recommended over raw key), Keychain, App Attest recommended | Network-bound; inference on provider's cloud, different privacy profile than PCC | N/A | **Apple requires naming the specific provider + explicit disclosure** if personal data is sent off-device | Only relevant if Lancer ever wants a frontier cloud model for the hardest cases — not needed for V1 of a Copilot | WWDC26 s339 | Med |
| `@Generable`/`@Guide` macros — structured output | iOS 26.0 baseline, unchanged in iOS 27 | N | — | `respond<Content: Generable>(...)`, `streamResponse<Content: Generable>(...)` | — | Reduces prompt-injection surface vs. free text | **The mechanism for a machine-readable `RiskVerdict`** — not free text | SDK L889-909, L1722-1784 | High |
| `Tool` protocol — local tool calling | iOS 26.0 baseline; tool-calling *quality* improved for iOS 27's rebuilt on-device model | N | — | `associatedtype Arguments: ConvertibleFromGeneratedContent`, arbitrary `async throws` body, fully general | App-process-local; app controls blast radius of what a tool returns | Model only sees what the tool chooses to return | **The mechanism for "retrieve evidence"** — implement `PastPolicyDecisionsTool`, `CommandHistoryTool`, `DiffContextTool`, `HostRiskHistoryTool` | SDK L2503-2511 | High |
| `Attachment<ImageAttachmentContent>` — image input | New in iOS 27 | N | — | Accepts `UIImage`/`CGImage`/file URL, any size (larger = more tokens/latency) | On-device only per WWDC26 s241 — **PCC image support not confirmed either way** | Screenshots may contain secrets (terminal output tokens); feeding them to any model is a real data-handling decision | Enables screenshot review of terminal/diff UI — genuinely new capability this cycle | SDK L2297-2321; WWDC26 s241 | High (existence); Med (PCC scope unconfirmed) |
| `LanguageModelSession.DynamicProfile` | New in iOS 27 | N (novel, least battle-tested primitive) | — | Declarative switching of instructions/tools/model/reasoning mid-session while preserving transcript; result-builder DSL | Session-scoped | — | Lets the Copilot run a cheap "quick triage" profile (on-device, light tools) vs. a "deep forensic" profile (PCC, `.deep`, full evidence toolset) selected by request risk tier, in one continuous session | SDK L590-705 | High |
| Fine-tuned on-device adapter (`SystemLanguageModel(adapter:guardrails:)`) | **`@available(iOS, obsoleted: 27.0)`** | N — removed, not beta | — | Explicitly dead as of iOS 27 | — | — | **Trap to avoid:** do not propose fine-tuning a custom adapter on `SystemLanguageModel` — that path no longer exists | SDK L296-303 | High — concrete, load-bearing finding |
| Core AI framework (custom on-device models) | New WWDC26 (sessions 324/326) | Y (first year) | Not independently SDK-verified | Converted PyTorch + pre-optimized OSS models, per WebSearch summary | — | Fully local — avoids sending command/diff data anywhere | Only relevant if Lancer wants a custom-trained deterministic classifier (e.g. fine-tuned on the team's own approve/deny history) rather than prompting a general LLM | WebSearch only | Low-Med |
| `MLXLanguageModel`/`CoreAILanguageModel` conformers | New WWDC26 | Y | Neural Engine/GPU via MLX | Loads mlx-community HF models into the same `LanguageModel` protocol | — | Fully local | Possible route to a smaller/faster specialized classifier speaking the same protocol as the rest of the Copilot | WebSearch only — **not found in the grepped `FoundationModels.framework` interface** | Low — unverified against ground truth |
| Evaluations framework (LLM output grading) | New WWDC26 | Y | — | Subject + dataset + metric + pass/fail evaluator, integrates with Swift Testing | — | — | Exactly the right tool to regression-test Copilot verdict quality before shipping prompt/schema changes | WWDC26 s241 — **no standalone `Evaluations.framework` found in the iOS 27 SDK**, may be package/Xcode-side only | Low-Med |
| App Review Guideline 5.1.2(i) — AI disclosure | Updated 2026-06-08 (WWDC26 day) | N (live policy) | — | Must name the specific 3rd-party AI provider if personal data is shared with one | — | Governs the Copilot only if it ever routes to a non-Apple cloud model | Moot if the Copilot stays on-device/PCC; binds only the (not-yet-buildable) 3rd-party routing path | WebSearch (multiple secondary sources) | Med |

## Approval Copilot feasibility — the five questions

**(a) Tool-calling against local app data.** **Yes, production-ready today.** The `Tool`
protocol is unchanged in core shape since iOS 26, with tool-calling quality explicitly improved
for iOS 27's rebuilt on-device model. Build native Swift `Tool` conformers over Lancer's existing
GRDB store — `PastPolicyDecisionTool` (query `daemon/lancerd/audit.go`'s hash-chained log),
`HostRiskHistoryTool`, `DiffContextTool`, `CommandHistoryTool` — no network call, no new
entitlement, no daemon change required. This is the strongest, most immediately buildable piece
of the whole feature.

**(b) Guided/structured generation for a reliable verdict.** **Yes — this is the framework's core
value-add for this use case.** `@Generable`/`@Guide` give schema-validated typed output. Define:

```swift
struct RiskVerdict: Generable {
    @Guide(description: "Risk classification of the pending agent request")
    var risk: RiskLevel  // .low / .medium / .high / .critical

    @Guide(description: "Copilot recommendation — never authoritative")
    var recommendation: Recommendation  // .approveOnce / .editFirst / .deny

    var rationale: String
    var flaggedConcerns: [String]
}
```

The deterministic policy engine and the human's own decision consume this typed value; the model
never gets to interpret its own free text or influence control flow beyond display. This directly
satisfies the "advisory, never authoritative" requirement structurally, not just by convention.

**(c) Image input for screenshot review.** **Yes, and genuinely new in iOS 27** — not carried over
from iOS 26. `Attachment<ImageAttachmentContent>` accepts a `UIImage`/`CGImage`/file URL at
arbitrary size, insertable into a `Prompt` via `PromptBuilder`. Unresolved and flagged
medium-confidence: whether `PrivateCloudComputeLanguageModel` also accepts image attachments —
not confirmed in the SDK interface either way. Verify before building screenshot review into the
`.deep` reasoning tier specifically.

**(d) Latency/quality on-device vs. cloud.** **Architecturally solvable via tiering, but
empirically unmeasured.** `DynamicProfile` lets a single session start cheap (on-device,
`.light`) for routine requests and escalate to `PrivateCloudComputeLanguageModel` with
`.deep` reasoning for requests that look destructive or ambiguous, without losing conversation
history. No latency numbers exist in any source consulted — **this must be benchmarked on a real
device before committing to a UX that blocks a human's approval decision on the Copilot's
response.** PCC's quota ceiling (free tier capped low) is a real production risk for a
review-gate feature that cannot afford to silently degrade under load — plan a graceful
"Copilot unavailable, policy engine still governs" fallback, not a hard dependency.

**(e) Apple guidance on liability for AI security recommendations.** **No guidance found specific
to this exact scenario.** What does exist: Guideline 5.1.2(i) requires naming a 3rd-party AI
provider by name if personal data is shared with one — only relevant if Lancer routes to a cloud
frontier model, which isn't needed for V1. Nothing addresses product-liability framing for an
advisory-only security AI. **Treat this as an open legal/App-Review question in
`10-open-questions.md`, not a settled fact** — do not let the report assert an answer that isn't
sourced.

## Proposed architecture for Lancer specifically

1. **Model routing:** on-device `SystemLanguageModel` as the default for every pending approval
   (fast, private, no quota risk); escalate to `PrivateCloudComputeLanguageModel` with
   `.deep` reasoning only when the on-device pass itself flags `risk: .high` or `.critical`, or
   when the command touches a path/pattern already on a sensitive-paths allowlist (mirrors the
   existing policy engine's own kind-based gating in `daemon/lancerd/policy/evaluate.go`).
2. **Evidence retrieval:** `Tool` conformers reading directly from the app's local GRDB store —
   no new daemon RPC needed for V1; the Copilot only needs what's already synced to the phone.
3. **Output contract:** a single `RiskVerdict: Generable` struct, rendered as a card **next to**,
   never replacing, the existing approve/reject UI (`DSApprovalBanner`, `InboxApprovalCard`).
4. **Failure behavior:** any Copilot failure — unavailable model, PCC quota exhausted, timeout —
   must degrade to "no Copilot opinion shown," never to blocking or auto-deciding the approval.
   The deterministic policy engine's ask/deny/allow defaults are completely unaffected.
5. **Evaluation:** before shipping, build a small internal eval corpus of past real
   approve/deny decisions (the daemon's hash-chained audit log is exactly this dataset) and grade
   the Copilot's verdict against the human's actual historical decision — Apple's WWDC26
   Evaluations framework is the natural fit if/when its packaging is confirmed (currently
   low-confidence — not found in the SDK, may be a separate package).

## What NOT to build (explicitly rejected)

- **A fine-tuned on-device adapter** (`SystemLanguageModel(adapter:guardrails:)`) — this API is
  `@available(iOS, obsoleted: 27.0)` in the shipped SDK. Dead path, don't propose it.
- **Routing agent command/diff/log content to a 3rd-party cloud model** (Anthropic/Google via the
  new `LanguageModel` protocol) for V1 — the conforming packages aren't shipped yet (beta/future),
  and it triggers a real App Review disclosure requirement for no clear V1 benefit over
  on-device/PCC.
- **Any code path where the Copilot's `RiskVerdict` can set an approval's outcome directly** — it
  must remain read-only advisory input to a human decision, full stop. This is both a security
  requirement (per the report's stated boundary) and consistent with Lancer's own fail-closed
  policy-engine design elsewhere in the codebase.
