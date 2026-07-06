#if os(iOS)
import SwiftUI

public enum CursorThreadAttention: Sendable {
    case needsApproval
    case awaitingInput
    case working
    case ready
    case failed
    case idle

    public var label: String {
        switch self {
        case .needsApproval: return "Needs Approval"
        case .awaitingInput: return "Awaiting Input"
        case .working: return "Working"
        case .ready: return "Ready"
        case .failed: return "Failed"
        case .idle: return "Idle"
        }
    }

    public func color(for scheme: CursorScheme) -> Color {
        let c = CursorColors.resolve(scheme)
        switch self {
        case .needsApproval: return c.riskHigh
        case .awaitingInput: return c.riskMedium
        case .working: return c.statusDotActive
        case .ready: return c.successGreen
        case .failed: return c.dangerRed
        case .idle: return c.mutedText
        }
    }
}
#endif
