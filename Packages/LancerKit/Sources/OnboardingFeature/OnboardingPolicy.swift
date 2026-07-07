#if os(iOS)
import Foundation
import LancerCore

// MARK: - Caution level (onboarding policy tiers)

/// The onboarding "How cautious?" tiers. Kept separate from `AutonomyPreset` because
/// the design's three labels (Cautious / Balanced / Bypass) don't map 1:1 onto the
/// existing policy enum — `mappedPreset` is the current best-effort bridge.
public enum OnboardingCautionLevel: String, CaseIterable, Identifiable, Sendable {
    case cautious
    case balanced
    case bypass

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .cautious: return "Cautious"
        case .balanced: return "Balanced"
        case .bypass:   return "Autonomous"
        }
    }

    public var detail: String {
        switch self {
        case .cautious: return "Approve every action myself"
        case .balanced: return "Auto-approve low-risk, ask the rest"
        case .bypass:   return "Only stop me for high-risk"
        }
    }

    public var recommended: Bool { self == .balanced }

    /// Clean 3-tier mapping onto the policy model (Balanced uses the dedicated `.autoSafeWrites`).
    public var mappedPreset: AutonomyPreset {
        switch self {
        case .cautious: return .autoReads
        case .balanced: return .autoSafeWrites
        case .bypass:   return .agentDecides
        }
    }
}

// MARK: - Onboarding → daemon policy bridge

/// Maps the onboarding "How cautious?" tier to a starter `~/.lancer/policy.yaml`
/// and applies it to the daemon exactly once, on the first successful connect.
///
/// The daemon isn't reachable during first-run pairing (the bridge is still being
/// paired over the relay), so the chosen tier is persisted locally at finish via
/// `markPending(_:)` and flushed by `applyPendingIfNeeded(save:)` from the
/// connect path. The push is idempotent — `appliedKey` guards re-pushes, and a
/// failed push leaves the pending flag set so the next connect retries.
public enum OnboardingPolicy {
    /// Last onboarding tier whose starter policy has not yet reached the daemon.
    static let pendingKey = "lancer.onboarding.pendingPolicyLevel"
    /// Set once the starter policy has been pushed + reloaded successfully.
    static let appliedKey = "lancer.onboarding.policyApplied"

    private static var defaults: UserDefaults { .standard }

    /// Record the chosen tier at onboarding finish. Clears `applied` so the next
    /// connect re-pushes (e.g. the user redid onboarding with a different tier).
    public static func markPending(_ level: OnboardingCautionLevel) {
        defaults.set(level.rawValue, forKey: pendingKey)
        defaults.set(false, forKey: appliedKey)
    }

    /// Push the pending starter policy once. `save` receives the YAML and is
    /// expected to persist + reload it on the daemon. No-op when nothing is
    /// pending or it was already applied.
    public static func applyPendingIfNeeded(
        save: @Sendable (_ yaml: String) async throws -> Void
    ) async {
        guard !defaults.bool(forKey: appliedKey),
              let raw = defaults.string(forKey: pendingKey),
              let level = OnboardingCautionLevel(rawValue: raw)
        else { return }
        do {
            try await save(level.policyYAML)
            defaults.set(true, forKey: appliedKey)
        } catch {
            // Leave pending — the next successful connect retries the push.
        }
    }
}

public extension OnboardingCautionLevel {
    /// Starter `~/.lancer/policy.yaml` for this tier. Schema + semantics match
    /// `docs/policy.example.yaml`: among matching rules, strictest wins
    /// (deny > ask > allow). Credentials are denied in every tier.
    var policyYAML: String {
        switch self {
        case .cautious:
            return """
            # Lancer starter policy — Cautious
            # Ask on every write, network call, and destructive action; deny secrets.
            default: ask

            rules:
              - id: deny-credential
                effect: deny
                kind: credential
              - id: allow-safe-reads
                effect: allow
                kind: command
                maxRisk: low
                match: "ls*"
            """
        case .balanced:
            return """
            # Lancer starter policy — Balanced (recommended)
            # Auto-allow safe reads + routine low-risk writes; ask on risky actions.
            default: ask

            rules:
              - id: deny-credential
                effect: deny
                kind: credential
              - id: deny-critical
                effect: deny
                maxRisk: critical
              - id: allow-low-shell
                effect: allow
                kind: command
                maxRisk: low
              - id: ask-network
                effect: ask
                kind: network
              - id: ask-destructive-git
                effect: ask
                match: "git push*"
                minRisk: medium
            """
        case .bypass:
            return """
            # Lancer starter policy — Bypass
            # Allow by default in trusted repos; ask only on critical actions.
            default: allow

            rules:
              - id: deny-credential
                effect: deny
                kind: credential
              - id: ask-critical
                effect: ask
                minRisk: critical
            """
        }
    }
}
#endif
