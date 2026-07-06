import Foundation
import LocalAuthentication
import LancerCore

/// Async gate over `LAContext` biometric authentication.
/// Fails closed on real devices without a passcode; simulators and XCTest hosts
/// may bypass when LocalAuthentication is unavailable.
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
            if let nsError, let laErr = nsError as? LAError {
                switch laErr.code {
                case .biometryNotEnrolled:
                    try await passcodeFallback(reason: reason)
                    return
                case .passcodeNotSet:
                    throw LancerError.authFailed(
                        reason: "A device passcode is required for authentication"
                    )
                default:
                    break
                }
            }
            if Self.allowsUnauthenticatedBypass {
                return
            }
            throw LancerError.authFailed(
                reason: nsError?.localizedDescription ?? "Authentication is not available"
            )
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
                            cont.resume(throwing: LancerError.cancelled)
                        case .biometryNotAvailable, .biometryNotEnrolled:
                            if Self.allowsUnauthenticatedBypass {
                                cont.resume()
                            } else {
                                Self.evaluatePasscodeFallback(
                                    reason: reason,
                                    continuation: cont
                                )
                            }
                        case .biometryLockout:
                            // Biometry IS enrolled but is locked out (too many failed
                            // attempts). Silently succeeding here would let anyone who
                            // deliberately fails Face/Touch ID five times force the gate
                            // open (app-lock + SSH key use). Require the device passcode
                            // instead — fail closed if it isn't satisfied.
                            Self.evaluatePasscodeFallback(
                                reason: reason,
                                continuation: cont
                            )
                        default:
                            cont.resume(throwing: LancerError.authFailed(
                                reason: laError.localizedDescription
                            ))
                        }
                    } else {
                        cont.resume(throwing: LancerError.authFailed(
                            reason: error.localizedDescription
                        ))
                    }
                } else if success {
                    cont.resume()
                } else {
                    cont.resume(throwing: LancerError.authFailed(
                        reason: "Biometric authentication denied"
                    ))
                }
            }
        }
    }

    private func passcodeFallback(reason: String) async throws {
        let ctx = LAContext()
        var nsError: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &nsError) else {
            if let nsError, let laErr = nsError as? LAError, laErr.code == .passcodeNotSet {
                throw LancerError.authFailed(
                    reason: "A device passcode is required for authentication"
                )
            }
            if Self.allowsUnauthenticatedBypass {
                return
            }
            throw LancerError.authFailed(
                reason: nsError?.localizedDescription ?? "Authentication is not available"
            )
        }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, any Error>) in
            Self.evaluatePasscodeFallback(reason: reason, continuation: cont)
        }
    }

    private static func evaluatePasscodeFallback(
        reason: String,
        continuation cont: CheckedContinuation<Void, any Error>
    ) {
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
                cont.resume(throwing: LancerError.cancelled)
            } else {
                cont.resume(throwing: LancerError.authFailed(
                    reason: passcodeError?.localizedDescription
                        ?? "Authentication failed"
                ))
            }
        }
    }

    /// Simulators and XCTest hosts lack a real LocalAuthentication stack.
    private static var allowsUnauthenticatedBypass: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        #endif
    }
}
