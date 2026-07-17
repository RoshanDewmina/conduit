import Foundation

/// Per-session autonomy preset: controls which approval requests are surfaced
/// to the user and which are handled automatically by the client.
public enum AutonomyPreset: String, CaseIterable, Sendable, Codable {
    /// Low-risk reads (exit-checks, git status, file reads) are approved
    /// automatically. All writes and destructive ops still ask the user.
    case autoReads

    /// Auto-approve low- and medium-risk actions ("safe writes"); ask on
    /// high/critical (deletes, network, secrets). The "Balanced" tier.
    case autoSafeWrites

    /// Every agent action surfaces an approval request, regardless of risk.
    case alwaysAsk

    /// Only `critical`-risk actions require manual approval.
    /// The agent's own risk assessment gates the rest.
    case agentDecides

    /// Full bypass — nothing pauses. Every action runs without asking, of any
    /// kind or risk. The deliberate "I'm driving, don't stop me" mode (the Claude
    /// Code bypassPermissions equivalent). Never inferred; only an explicit,
    /// owner-set choice produces it, and a conversation in this mode shows a
    /// persistent indicator. Actions are still audited.
    case bypass

    public var label: String {
        switch self {
        case .autoReads:      return "Auto-approve reads"
        case .autoSafeWrites: return "Auto-approve safe writes"
        case .alwaysAsk:      return "Always ask"
        case .agentDecides:   return "Critical only"
        case .bypass:         return "Full bypass"
        }
    }

    public var shortLabel: String {
        switch self {
        case .autoReads:      return "Auto-reads"
        case .autoSafeWrites: return "Safe writes"
        case .alwaysAsk:      return "Always ask"
        case .agentDecides:   return "Critical only"
        case .bypass:         return "Full bypass"
        }
    }

    public var description: String {
        switch self {
        case .autoReads:
            return "Read-only operations are approved automatically. Writes and destructive actions always ask."
        case .autoSafeWrites:
            return "Low- and medium-risk actions run automatically. Deletes, network, and secret-touching actions still ask."
        case .alwaysAsk:
            return "Every agent action requires your approval before it runs."
        case .agentDecides:
            return "Only critical-risk actions ask. Low, medium, and high-risk actions can run automatically."
        case .bypass:
            return "Nothing pauses — the agent runs every action without asking. Use only while you're driving this machine yourself."
        }
    }

    /// Returns `true` if an approval with `risk` should be auto-approved
    /// under this preset without surfacing the inbox card.
    public func isAutoApproved(kind: Approval.Kind, risk: Approval.Risk) -> Bool {
        switch self {
        case .alwaysAsk:
            return false
        case .autoReads:
            return risk == .low && (kind == .command || kind == .callMCP)
        case .autoSafeWrites:
            // "Safe writes": auto-approve low/medium risk of any kind; high &
            // critical (deletes, network, secrets) still surface.
            return risk <= .medium
        case .agentDecides:
            return risk < .critical
        case .bypass:
            // Nothing surfaces — every action is auto-approved.
            return true
        }
    }

    // MARK: - Coarse relay permission mode

    /// Maps this UI preset onto the daemon's coarse policy `default`
    /// (`deny` / `ask` / `allow`) for `agentPermissionModeSet`.
    ///
    /// The daemon's named `PresetDocument`s (`cautious` / `balanced` /
    /// `bypass` in `policy/types.go`) encode richer per-rule YAML, but the
    /// relay RPC can only write the document-level `default`. Closest
    /// coarse effects (fail-closed — any ambiguity → `.ask`):
    /// - `.bypass` → `.allow` (matches onboarding bypass starter YAML
    ///   `default: allow`; full "don't stop me" intent)
    /// - `.autoSafeWrites` (balanced), `.autoReads` (cautious),
    ///   `.alwaysAsk`, `.agentDecides` → `.ask`
    ///
    /// No AutonomyPreset maps to `.deny`; that coarse mode is Settings-only.
    public var coarsePermissionMode: PermissionMode {
        switch self {
        case .bypass:
            return .allow
        case .autoReads, .autoSafeWrites, .alwaysAsk, .agentDecides:
            return .ask
        }
    }

    /// Best AutonomyPreset to display for a daemon-confirmed coarse mode.
    /// Prefer `preferred` when it already maps to `mode` so a finer UI label
    /// (e.g. Always ask vs Safe writes) survives a round-trip that both map
    /// to `.ask`. Fail-closed: unknown / `.deny` → `.alwaysAsk`.
    public static func reflecting(
        coarseMode mode: PermissionMode,
        preferred: AutonomyPreset = .autoSafeWrites
    ) -> AutonomyPreset {
        switch mode {
        case .allow:
            return .bypass
        case .ask:
            return preferred.coarsePermissionMode == .ask ? preferred : .autoSafeWrites
        case .deny:
            return .alwaysAsk
        }
    }
}
