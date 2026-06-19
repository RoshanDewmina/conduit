# M4 SessionViewModel patch

Changes to apply to `Sources/SessionFeature/SessionViewModel.swift`:

## 1. Import AgentKit (if not already imported)

```swift
import AgentKit
```

## 2. Replace direct `ai.complete(prompt: ...)` calls with PromptBuilder

For the NL→command translation path (when `inputText` starts with `#`):

```swift
let built = PromptBuilder.nlToCommand(intent: userInput, context: recentOutput)
let response = try await ai.complete(
    messages: [.user(built.userContent)],
    system: built.systemPrompt,
    maxTokens: 256
)
```

## 3. For explain-error flow, use `PromptBuilder.explainError(...)`

Replace any ad-hoc explain prompts with:

```swift
let built = PromptBuilder.explainError(
    command: block.command,
    output: block.joinedOutput,
    exitCode: block.exitStatus?.code ?? -1
)
// Then stream using built.systemPrompt + built.userContent
// Pass built.report to ExplainSheet
```

## 4. Add session token usage tracking

```swift
public private(set) var sessionTokenUsage: TokenUsage = .zero
```

## 5. After each AI call, update token usage

```swift
sessionTokenUsage = await ai.latestTokenUsage()
```

> Note: `AnthropicClient` is an `actor`, so `latestTokenUsage()` requires `await`
> when called from outside the actor. If `ai` is stored as `any AIClient` (which
> is `Sendable` but not an actor), you may need to cast or restructure.
> The simplest approach: add `func latestTokenUsage() async -> TokenUsage` to the
> protocol, with a default `{ .zero }` implementation.

## 6. Pass `RedactionReport` to ExplainSheet

When presenting `ExplainSheet`, pass the `report` from `PromptBuilder.explainError(...)`:

```swift
// In SessionView, replace the inline explainSheet(...) with:
ExplainSheet(
    command: block.command,
    output: block.joinedOutput,
    exitCode: block.exitStatus?.code ?? -1,
    report: explainReport,       // RedactionReport from PromptBuilder
    onDismiss: { explainTarget = nil }
)
```

Store `explainReport` as `@State private var explainReport: RedactionReport = RedactionReport(redactedCount: 0, matchedPatterns: [])` and populate it before setting `explainTarget`.

## Note on existing inline explain sheet in SessionView.swift

`SessionView.swift` contains an inline `explainSheet(block:)` function at line 139
that implements similar functionality. Once `SessionViewModel` is wired to use
`PromptBuilder` and `ExplainSheet`, the inline `explainSheet` function and the
`explainText`/`isExplaining` state vars can be removed. The `ExplainSheet` component
in `SessionFeature/ExplainSheet.swift` is the canonical replacement.
