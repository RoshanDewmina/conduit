#if os(iOS)
import Foundation

@available(iOS 16.2, *)
public enum LiveActivityPrimaryState: Equatable {
    case needsYou(count: Int)
    case decisionLanded(approved: Bool)
    case running
    case idle
}

public enum CostLevel: Equatable { case none, normal, warning, over }

/// Pure, UI-free resolution of a ContentState into the single primary state to
/// render plus the cost overlay level. Keeps precedence logic out of the widget
/// (which stays pure presentation) and makes it unit-testable without ActivityKit.
@available(iOS 16.2, *)
public struct LiveActivityPresentation: Equatable {
    public let primary: LiveActivityPrimaryState
    public let cost: Double?
    public let costLevel: CostLevel

    public static func resolve(
        _ state: ConduitSessionAttributes.ContentState,
        budget: Double?
    ) -> LiveActivityPresentation {
        let primary: LiveActivityPrimaryState
        if state.pendingApprovals > 0 {
            primary = .needsYou(count: state.pendingApprovals)
        } else if let d = state.lastDecision {
            primary = .decisionLanded(approved: d == "approved")
        } else if state.isStreaming {
            primary = .running
        } else {
            primary = .idle
        }

        let level: CostLevel
        if let c = state.cost, c > 0 {
            if let b = budget, b > 0 {
                if c >= b { level = .over }
                else if c >= 0.8 * b { level = .warning }
                else { level = .normal }
            } else {
                level = .normal
            }
        } else {
            level = .none
        }

        return LiveActivityPresentation(primary: primary, cost: state.cost, costLevel: level)
    }
}
#endif
