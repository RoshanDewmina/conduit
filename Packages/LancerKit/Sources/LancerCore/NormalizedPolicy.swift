import Foundation

/// The agent CLIs Lancer can dispatch to. Mirrors the adapter cases in
/// `daemon/lancerd/dispatch.go` (claude / codex / opencode); Kimi is intentionally
/// out of scope for normalized policy until its hook story lands.
public enum AgentProvider: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case claudeCode
    case codex
    case openCode

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex:      "Codex"
        case .openCode:   "OpenCode"
        }
    }

    /// Short column label for a compact matrix header.
    public var shortName: String {
        switch self {
        case .claudeCode: "Claude"
        case .codex:      "Codex"
        case .openCode:   "OpenCode"
        }
    }
}

/// How a single normalized rule is realized on a given provider.
///
/// Grounded in the daemon's gating model: Claude Code and OpenCode expose a
/// per-action `PreToolUse` hook (`isHookCapableAgent` in dispatch.go), so a rule
/// can be enforced inline as a `hook`. Codex has no per-action hook — it gates
/// through its non-interactive `exec` approval flow, so its rules map to
/// `approval`. Where a provider can express neither, the rule is `unsupported`
/// and the matrix surfaces it as a gap.
public enum RuleMapping: String, Codable, Hashable, Sendable {
    case hook
    case approval
    case unsupported
}

/// One provider-agnostic guardrail authored once and projected onto every agent.
public struct NormalizedRule: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let description: String
    /// Coarse risk level (0 low → 3 critical), reused by the matrix for status tone.
    public let riskLevel: Int

    public init(id: String, description: String, riskLevel: Int) {
        self.id = id
        self.description = description
        self.riskLevel = riskLevel
    }
}

/// An ordered set of normalized rules that can be mapped across providers and
/// applied to all of them at once.
public struct NormalizedPolicy: Codable, Hashable, Sendable {
    public let rules: [NormalizedRule]

    public init(rules: [NormalizedRule]) {
        self.rules = rules
    }

    /// How `rule` is realized on `provider`.
    ///
    /// This is a deterministic lookup, not a heuristic:
    /// - Claude Code has a verifiably-wired `PreToolUse` hook for every tool call,
    ///   so all rules enforce as `hook`.
    /// - Codex has no per-action hook; it can only gate via its `exec` approval
    ///   prompt, so all rules map to `approval`.
    /// - OpenCode also runs through a hook, but its hook install only covers
    ///   command/tool interception — it cannot enforce a write-target *scope*
    ///   restriction (e.g. "escalate prod writes"), which the daemon would have to
    ///   approve out-of-band instead. Scope-based rules are therefore `unsupported`
    ///   there until the OpenCode hook gains path awareness.
    public func mapping(for rule: NormalizedRule, provider: AgentProvider) -> RuleMapping {
        switch provider {
        case .claudeCode:
            return .hook
        case .codex:
            return .approval
        case .openCode:
            return ruleIsScopeBased(rule) ? .unsupported : .hook
        }
    }

    /// Scope-based rules constrain *where* an action may write/run rather than
    /// *whether* a tool runs; the OpenCode hook can't yet see those targets.
    private func ruleIsScopeBased(_ rule: NormalizedRule) -> Bool {
        Self.scopeBasedRuleIDs.contains(rule.id)
    }

    private static let scopeBasedRuleIDs: Set<String> = [
        "escalate-prod-writes",
        "block-secret-exfil",
    ]

    /// A realistic default rule set covering the guardrails most teams want first.
    public static var defaultPolicy: NormalizedPolicy {
        NormalizedPolicy(rules: [
            NormalizedRule(
                id: "no-rm-rf-outside-tmp",
                description: "Deny rm -rf outside /tmp",
                riskLevel: 3
            ),
            NormalizedRule(
                id: "escalate-prod-writes",
                description: "Escalate writes to prod paths",
                riskLevel: 3
            ),
            NormalizedRule(
                id: "ask-network-installs",
                description: "Ask before network package installs",
                riskLevel: 1
            ),
            NormalizedRule(
                id: "block-secret-exfil",
                description: "Block reads of secret/credential files",
                riskLevel: 2
            ),
        ])
    }
}
