import Foundation
import LancerCore

/// Pure transcript assembly for `LiveThreadView` — which turns render as
/// frozen history vs which one binds to live `sendState`.
public enum LiveThreadTranscript: Sendable {
    /// Turns whose assistant side should render from stored text (not sendState).
    /// Excludes `liveTurnID` when known; when nil and the last turn is still
    /// `.running`, excludes that last turn so working/streaming can bind to it.
    public static func priorTurns(turns: [ChatTurn], liveTurnID: String?) -> [ChatTurn] {
        if let liveTurnID {
            return turns.filter { $0.id != liveTurnID }
        }
        if let last = turns.last, last.status == .running {
            return Array(turns.dropLast())
        }
        return turns
    }

    /// The turn currently bound to live sendState, if any.
    public static func liveTurn(turns: [ChatTurn], liveTurnID: String?) -> ChatTurn? {
        if let liveTurnID {
            return turns.first { $0.id == liveTurnID }
        }
        if let last = turns.last, last.status == .running {
            return last
        }
        return nil
    }

    /// Observed-continue adoption opens `LiveThreadView` with an empty prompt —
    /// skip the initial `send` so the first typed follow-up performs continue.
    public static func shouldSendInitialPrompt(_ prompt: String) -> Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// After a successful observed-session adopt, an empty host transcript must
    /// still keep the composer usable but must not render a blank thread.
    public static func shouldShowAdoptedNoHistoryPlaceholder(transcriptMessageCount: Int) -> Bool {
        transcriptMessageCount == 0
    }

    static func isObservedWrapperUserText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("<local-command-caveat>")
            || trimmed.hasPrefix("<local-command-stdout>")
            || trimmed.hasPrefix("<command-name>")
            || trimmed.hasPrefix("<command-message>")
            || trimmed.hasPrefix("<system-reminder>")
            || trimmed.hasPrefix("<task-notification>")
    }

    static func shouldRenderTurn(
        _ turn: ChatTurn,
        hasAssistantArtifacts: Bool = false
    ) -> Bool {
        guard isObservedWrapperUserText(turn.prompt) else { return true }
        return assistantFallback(for: turn) != nil || hasAssistantArtifacts
    }

    static func shouldRenderPromptBubble(for turn: ChatTurn) -> Bool {
        if !turn.attachments.isEmpty { return true }
        return !isObservedWrapperUserText(turn.prompt)
    }

    static func assistantFallback(for turn: ChatTurn) -> String? {
        turn.assistantText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : turn.assistantText
    }

    /// Pairs flat `agent.sessions.transcript` messages into `ChatTurn` rows for
    /// the live thread's frozen history (user bubble + assistant body).
    public static func turns(
        fromObservedMessages messages: [SessionMessage],
        conversationID: String,
        vendorSessionID: String
    ) -> [ChatTurn] {
        var turns: [ChatTurn] = []
        var prompt = ""
        var assistantText = ""
        var open = false

        func flush() {
            guard open else { return }
            let ordinal = turns.count
            turns.append(
                ChatTurn(
                    conversationID: conversationID,
                    ordinal: ordinal,
                    prompt: prompt,
                    runID: "observed:\(vendorSessionID):\(ordinal)",
                    transportKind: "relay",
                    status: .completed,
                    assistantText: assistantText,
                    completedAt: .now,
                    vendorSessionID: vendorSessionID
                )
            )
            prompt = ""
            assistantText = ""
            open = false
        }

        for message in messages {
            switch message.role {
            case .user:
                if open { flush() }
                prompt = message.text
                open = true
            case .assistant:
                if !open {
                    open = true
                }
                if assistantText.isEmpty {
                    assistantText = message.text
                } else {
                    assistantText += "\n\n" + message.text
                }
            case .toolCall, .toolResult:
                if !open {
                    open = true
                }
                // Text already carries the tool summary (e.g. "Bash: ls -la") from
                // the daemon adapter — do not also prepend toolName or it doubles.
                let chunk = message.text
                if assistantText.isEmpty {
                    assistantText = chunk
                } else {
                    assistantText += "\n\n" + chunk
                }
            case .system, .unknown, .thinking:
                // Extended-thinking blocks are internal reasoning, not part of
                // the vendor-visible conversation — omit them from the
                // resumed transcript same as system/unknown lines.
                break
            }
        }
        flush()
        return turns
    }
}
