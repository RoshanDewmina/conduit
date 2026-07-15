import Foundation

/// Per-dispatch "Full tools" opt-in for a claudeCode turn — mirrors Go's
/// `dispatchParams.FullTools` / `conversationAppendRequest.FullTools`
/// (daemon/lancerd/dispatch.go, conversation_store.go). Default OFF: a phone
/// chat turn launches with `--strict-mcp-config` (fast — no MCP tool-schema
/// system-prompt cost), same as every claudeCode dispatch since the
/// 2026-07-14 latency fix. Flipping this ON for one send re-enables normal
/// MCP loading (XcodeBuildMCP/apple-docs/context7/…) for that turn only, at
/// the cost of first-token latency — real coding dispatches need the tools;
/// plain chat doesn't.
///
/// Persisted globally (matches `DispatchVendorSelection`/`DispatchModelSelection` —
/// neither is scoped per-workspace today), not per-conversation: the toggle
/// reflects the composer's current intent for the NEXT turn, not a property
/// of any one conversation.
public enum FullToolsSelection {
    public static let storageKey = "lancer.dispatch.fullTools"
    public static let `default` = false

    public static func load(from defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: storageKey) == nil ? `default` : defaults.bool(forKey: storageKey)
    }

    public static func save(_ enabled: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: storageKey)
    }
}
