import AppIntents
import Foundation

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
}
