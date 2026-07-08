import AppIntents
import Foundation

/// Which CLI agent `StartAgentRunIntent` should dispatch — mirrors the vendor
/// strings `DispatchAgent.vendor`/`AppRoot.resolveAgentTransport` already
/// switch on ("claudeCode", "codex", "opencode", "kimi"), so `relayVendor`
/// round-trips straight into `RunDispatchService.startRun(vendor:)` with no
/// translation table to keep in sync.
@available(iOS 17.0, *)
public enum AgentVendorAppEnum: String, AppEnum, Sendable {
    case claudeCode
    case codex
    case opencode
    case kimi

    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Agent")
    public static let caseDisplayRepresentations: [AgentVendorAppEnum: DisplayRepresentation] = [
        .claudeCode: "Claude Code",
        .codex: "Codex",
        .opencode: "OpenCode",
        .kimi: "Kimi",
    ]

    public var relayVendor: String { rawValue }

    public var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        case .opencode: return "OpenCode"
        case .kimi: return "Kimi"
        }
    }
}
