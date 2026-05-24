import Foundation
import LocalAuthentication
import ConduitCore

/// Async gate over `LAContext` biometric authentication.
/// Gracefully skips on simulators and devices without biometrics enrolled.
public actor BiometricGate: Sendable {
    public static let shared = BiometricGate()
    private init() {}

    public func unlock(
        reason: String = "Authenticate to use your SSH key"
    ) async throws {
        let ctx = LAContext()
        var nsError: NSError?
        guard ctx.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics, error: &nsError
        ) else {
            return  // No biometrics available (simulator, no Touch/Face ID enrolled)
        }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, any Error>) in
            ctx.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            ) { success, error in
                if let error {
                    if let laError = error as? LAError {
                        switch laError.code {
                        case .userCancel, .appCancel, .systemCancel:
                            cont.resume(throwing: ConduitError.cancelled)
                        case .biometryNotAvailable, .biometryNotEnrolled, .biometryLockout:
                            cont.resume()  // Degrade gracefully
                        default:
                            cont.resume(throwing: ConduitError.authFailed(
                                reason: laError.localizedDescription
                            ))
                        }
                    } else {
                        cont.resume(throwing: ConduitError.authFailed(
                            reason: error.localizedDescription
                        ))
                    }
                } else if success {
                    cont.resume()
                } else {
                    cont.resume(throwing: ConduitError.authFailed(
                        reason: "Biometric authentication denied"
                    ))
                }
            }
        }
    }
}
