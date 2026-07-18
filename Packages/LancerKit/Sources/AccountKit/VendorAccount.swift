import Foundation

/// Metadata-only vendor CLI account entry persisted on the phone.
/// Never stores passwords or API keys — credential swap is Mac-side (future daemon RPC).
public struct VendorAccount: Codable, Sendable, Identifiable, Equatable, Hashable {
    public let id: String
    /// Daemon / wire vendor id (`claudeCode`, `codex`, `opencode`, `kimi`, `pi`).
    public let vendor: String
    public var label: String
    /// Email or handle shown in the switcher — not a secret.
    public var handle: String
    public let createdAt: Date
    public var lastSelectedAt: Date?

    public init(
        id: String = UUID().uuidString,
        vendor: String,
        label: String,
        handle: String,
        createdAt: Date = .now,
        lastSelectedAt: Date? = nil
    ) {
        self.id = id
        self.vendor = vendor
        self.label = label
        self.handle = handle
        self.createdAt = createdAt
        self.lastSelectedAt = lastSelectedAt
    }
}

/// Vendors the Accounts & Usage screen lists. Wire ids mirror the daemon
/// (`dispatch.go` / `normalizeAgentSource`).
public enum VendorAccountVendor: String, CaseIterable, Sendable, Codable, Hashable {
    case claudeCode
    case codex
    case opencode
    case kimi
    case pi

    public var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .opencode: "OpenCode"
        case .kimi: "Kimi"
        case .pi: "Pi"
        }
    }

    public var systemImage: String {
        switch self {
        case .claudeCode: "sparkles"
        case .codex: "chevron.left.forwardslash.chevron.right"
        case .opencode: "terminal"
        case .kimi: "moon.stars"
        case .pi: "circle.hexagongrid"
        }
    }
}
