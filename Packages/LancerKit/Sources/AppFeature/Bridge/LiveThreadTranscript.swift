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
}
