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
            if let nsError, let laErr = nsError as? LAError,
               laErr.code == .biometryNotEnrolled {
                try await passcodeFallback(reason: reason)
                return
            }
            return  // Simulator or no passcode — degrade gracefully
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
                        case .biometryNotAvailable, .biometryNotEnrolled:
                            cont.resume()
                        case .biometryLockout:
                            // Biometry IS enrolled but is locked out (too many failed
                            // attempts). Silently succeeding here would let anyone who
                            // deliberately fails Face/Touch ID five times force the gate
                            // open (app-lock + SSH key use). Require the device passcode
                            // instead — fail closed if it isn't satisfied.
                            let passcodeCtx = LAContext()
                            passcodeCtx.evaluatePolicy(
                                .deviceOwnerAuthentication,
                                localizedReason: reason
                            ) { ok, passcodeError in
                                if ok {
                                    cont.resume()
                                } else if let passcodeError = passcodeError as? LAError,
                                          passcodeError.code == .userCancel
                                            || passcodeError.code == .appCancel
                                            || passcodeError.code == .systemCancel {
                                    cont.resume(throwing: ConduitError.cancelled)
                                } else {
                                    cont.resume(throwing: ConduitError.authFailed(
                                        reason: passcodeError?.localizedDescription
                                            ?? "Authentication failed"
                                    ))
                                }
                            }
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

    private func passcodeFallback(reason: String) async throws {
        let ctx = LAContext()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, any Error>) in
            ctx.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            ) { success, error in
                if let error {
                    cont.resume(throwing: ConduitError.authFailed(
                        reason: error.localizedDescription
                    ))
                } else if success {
                    cont.resume()
                } else {
                    cont.resume(throwing: ConduitError.authFailed(
                        reason: "Authentication required"
                    ))
                }
            }
        }
    }
}
