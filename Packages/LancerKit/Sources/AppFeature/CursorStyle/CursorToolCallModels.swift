import Foundation

/// Lifecycle of a single agent tool call, mirrored from Happier's
/// `ToolCall.state: running|completed|error` (patterns only — no verbatim code).
public enum CursorToolCallState: String, Sendable, Equatable {
    case running
    case completed
    case error
}

/// One foldable tool-call card in the CursorStyle transcript.
public struct CursorToolCallCard: Identifiable, Sendable, Equatable {
    public let id: String
    public var name: String
    public var state: CursorToolCallState
    public var inputJSON: String
    public var resultPreview: String?

    public init(
        id: String,
        name: String,
        state: CursorToolCallState,
        inputJSON: String,
        resultPreview: String? = nil
    ) {
        self.id = id
        self.name = name
        self.state = state
        self.inputJSON = inputJSON
        self.resultPreview = resultPreview
    }

    public var inputSummary: String {
        CursorToolCallPresentation.summarizeToolInput(inputJSON)
    }

    public var oneLineLabel: String {
        let brief = CursorToolCallPresentation.briefToolArg(inputJSON)
        if brief.isEmpty { return name }
        return "\(name) \(brief)"
    }
}

/// Foldable group of tool cards for one turn (Orca "N tool calls" run).
public struct CursorToolCallGroup: Sendable, Equatable {
    public let cards: [CursorToolCallCard]
    public let summaryLine: String
    public let shouldAutoExpand: Bool

    public init(cards: [CursorToolCallCard], summaryLine: String, shouldAutoExpand: Bool) {
        self.cards = cards
        self.summaryLine = summaryLine
        self.shouldAutoExpand = shouldAutoExpand
    }

    public var isEmpty: Bool { cards.isEmpty }
}

/// Mutually exclusive working-indicator for the live overlay. Never shown
/// alongside visible streamed assistant text (Orca mutual-exclusivity rule).
///
/// Derived from live hook + tool state — labels describe what was asked of the
/// agent, not a guaranteed outcome.
public enum CursorWorkingIndicator: Sendable, Equatable {
    case starting
    case thinking
    case toolRunning(name: String)
    case streaming

    public var displayLabel: String {
        switch self {
        case .starting: return "Starting…"
        case .thinking: return "Thinking…"
        case .streaming: return "Streaming…"
        case .toolRunning(let name):
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Running tool…" : "Running \(trimmed)…"
        }
    }

    /// Resolve the single indicator to show. Returns `nil` when assistant text
    /// is already visible so the indicator never coexists with streamed prose.
    ///
    /// Precedence (no visible text): toolRunning → streaming → thinking → starting.
    /// Inspired by Orca `native-chat-live-status.ts` live-override precedence
    /// (MIT; attribution: stablyai/orca).
    public static func resolve(
        isWorking: Bool,
        hasVisibleText: Bool,
        runningToolName: String?,
        streamConnected: Bool
    ) -> CursorWorkingIndicator? {
        if hasVisibleText { return nil }
        if let name = runningToolName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return .toolRunning(name: name)
        }
        if isWorking {
            return streamConnected ? .streaming : .thinking
        }
        return .starting
    }
}
