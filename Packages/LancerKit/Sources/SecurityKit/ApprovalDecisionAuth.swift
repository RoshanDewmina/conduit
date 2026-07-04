import Foundation
import LancerCore

/// Local-auth gate for approval decisions: a high/critical-risk approve or
/// reject must not commit without a fresh biometric/passcode unlock, so a
/// person holding an unlocked phone (or a stale Live Activity tap) can't
/// resolve the most dangerous gates silently. The tier split mirrors the
/// daemon's `policy.PermitsNoClientGrace` (low/medium = fast path, high/critical
/// = explicit human ceremony) rather than inventing a new scheme; low/medium
/// decisions stay one-tap because they are the product's core loop.
public enum ApprovalDecisionAuth {
    /// Unknown risk (no local row to read a tier from — e.g. a cold-launch
    /// decision for an approval this device never persisted) fails closed and
    /// requires the unlock.
    public static func requiresUnlock(risk: Approval.Risk?) -> Bool {
        guard let risk else { return true }
        return risk >= .high
    }

    /// Returns `true` when the decision may commit. Runs `unlock` only for
    /// tiers `requiresUnlock` gates; any thrown error (cancel, failed
    /// biometry+passcode) blocks the decision — the gate stays pending and the
    /// user can retry.
    public static func authorize(
        risk: Approval.Risk?,
        unlock: ((String) async throws -> Void)? = nil
    ) async -> Bool {
        guard requiresUnlock(risk: risk) else { return true }
        let reason = "Authenticate to resolve a high-risk approval"
        do {
            if let unlock {
                try await unlock(reason)
            } else {
                try await BiometricGate.shared.unlock(reason: reason)
            }
            return true
        } catch {
            return false
        }
    }
}
