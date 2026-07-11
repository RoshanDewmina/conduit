import Foundation

/// Claude Code models the New Chat composer can dispatch with.
/// Persisted under `lancer.dispatch.model` as short CLI aliases
/// (`haiku` / `sonnet` / `opus`) that `normalizeClaudeModel` accepts.
public enum DispatchModelSelection: String, CaseIterable, Sendable, Hashable {
    case haiku
    case sonnet
    case opus

    public static let storageKey = "lancer.dispatch.model"
    public static let `default`: DispatchModelSelection = .haiku

    public var slug: String { rawValue }

    public var displayName: String {
        switch self {
        case .haiku: "Haiku"
        case .sonnet: "Sonnet"
        case .opus: "Opus"
        }
    }

    public static func resolve(_ raw: String?) -> DispatchModelSelection {
        guard let raw else { return .default }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .default }
        return DispatchModelSelection(rawValue: trimmed.lowercased()) ?? .default
    }

    public static func load(from defaults: UserDefaults = .standard) -> DispatchModelSelection {
        resolve(defaults.string(forKey: storageKey))
    }

    public static func save(_ model: DispatchModelSelection, to defaults: UserDefaults = .standard) {
        defaults.set(model.rawValue, forKey: storageKey)
    }

    /// Follow-ups keep the conversation's original model; fall back to the
    /// current picker selection when the conversation has none stored.
    public static func modelForFollowUp(
        conversationModel: String?,
        selected: DispatchModelSelection
    ) -> String {
        let trimmed = conversationModel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { return trimmed }
        return selected.slug
    }
}
