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
                let label = message.toolName.map { "\($0)\n" } ?? ""
                let chunk = label + message.text
                if assistantText.isEmpty {
                    assistantText = chunk
                } else {
                    assistantText += "\n\n" + chunk
                }
            case .system, .unknown:
                break
            }
        }
        flush()
        return turns
    }
}
