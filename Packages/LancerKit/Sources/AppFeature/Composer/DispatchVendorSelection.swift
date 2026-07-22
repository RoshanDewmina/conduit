import Foundation

/// Vendor CLI the New Chat composer dispatches through.
/// Wire ids match `normalizeAgentSource` / `installedAgents` / Siri
/// `AgentVendorAppEnum` (`claudeCode`, `codex`, `opencode`, `kimi`, `cursor`).
public enum DispatchVendorSelection: String, CaseIterable, Sendable, Hashable {
    case claudeCode
    case codex
    case opencode
    case kimi
    case cursor

    public static let storageKey = "lancer.dispatch.vendor"
    public static let `default`: DispatchVendorSelection = .claudeCode

    public var wireID: String { rawValue }

    public var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .opencode: "OpenCode"
        case .kimi: "Kimi"
        case .cursor: "Cursor"
        }
    }

    public var systemImage: String {
        switch self {
        case .claudeCode: "sparkles"
        case .codex: "chevron.left.forwardslash.chevron.right"
        case .opencode: "terminal"
        case .kimi: "moon.stars"
        case .cursor: "hammer"
        }
    }

    /// Claude models (haiku/sonnet/opus) only apply to Claude Code.
    public var usesClaudeModelPicker: Bool { self == .claudeCode }

    public static func resolve(_ raw: String?) -> DispatchVendorSelection {
        guard let raw else { return .default }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .default }
        return DispatchVendorSelection(rawValue: trimmed) ?? .default
    }

    public static func load(from defaults: UserDefaults = .standard) -> DispatchVendorSelection {
        resolve(defaults.string(forKey: storageKey))
    }

    public static func save(_ vendor: DispatchVendorSelection, to defaults: UserDefaults = .standard) {
        defaults.set(vendor.rawValue, forKey: storageKey)
    }

    /// Vendors to offer in the picker. When `installed` is nil/empty (RPC not
    /// yet fetched), show the full catalog so the UI is usable offline; when
    /// the host reported a list, filter to those wire ids (plus keep the
    /// current selection visible so a previously chosen vendor doesn't vanish).
    public static func available(
        installed: [String]?,
        keeping selected: DispatchVendorSelection
    ) -> [DispatchVendorSelection] {
        guard let installed, !installed.isEmpty else {
            return Array(allCases)
        }
        let installedSet = Set(installed)
        var out = allCases.filter { installedSet.contains($0.wireID) }
        if !out.contains(selected) {
            out.insert(selected, at: 0)
        }
        return out
    }
}
