import Foundation
import LocalAuthentication
import LancerCore

/// Async gate over `LAContext` biometric authentication.
public actor BiometricGate: Sendable {
    public static let shared = BiometricGate()

    private let authenticator: any BiometricGateAuthenticating

    init(authenticator: any BiometricGateAuthenticating = LiveBiometricGateAuthenticator()) {
        self.authenticator = authenticator
    }

    public func unlock(
        reason: String = "Authenticate to use your SSH key"
    ) async throws {
        switch await authenticator.canEvaluateBiometrics() {
        case .available:
            break
        case .unavailable(let failure):
            guard failure.code == .biometryNotEnrolled else {
                throw authError(from: failure)
            }
            try await passcodeFallback(reason: reason)
            return
        }

        switch await authenticator.evaluateBiometrics(reason: reason) {
        case .success:
            return
        case .failure(let failure):
            switch failure.code {
            case .userCancel, .appCancel, .systemCancel:
                throw LancerError.cancelled
            case .biometryNotEnrolled, .biometryLockout:
                try await passcodeFallback(reason: reason)
            default:
                throw authError(from: failure)
            }
        }
    }

    private func passcodeFallback(reason: String) async throws {
        switch await authenticator.evaluateDeviceOwnerAuthentication(reason: reason) {
        case .success:
            return
        case .failure(let failure):
            throw authError(from: failure)
        }
    }

    private func authError(from failure: BiometricGateAuthFailure) -> LancerError {
        if failure.code == .userCancel
            || failure.code == .appCancel
            || failure.code == .systemCancel {
            return .cancelled
        }
        return .authFailed(reason: failure.reason)
    }
}

protocol BiometricGateAuthenticating: Sendable {
    func canEvaluateBiometrics() async -> BiometricGateAvailability
    func evaluateBiometrics(reason: String) async -> BiometricGateEvaluationResult
    func evaluateDeviceOwnerAuthentication(reason: String) async -> BiometricGateEvaluationResult
}

enum BiometricGateAvailability: Sendable, Equatable {
    case available
    case unavailable(BiometricGateAuthFailure)
}

enum BiometricGateEvaluationResult: Sendable, Equatable {
    case success
    case failure(BiometricGateAuthFailure)
}

struct BiometricGateAuthFailure: Sendable, Equatable {
    let code: LAError.Code?
    let reason: String
}

private struct LiveBiometricGateAuthenticator: BiometricGateAuthenticating {
    func canEvaluateBiometrics() async -> BiometricGateAvailability {
        let ctx = LAContext()
        var nsError: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &nsError) else {
            return .unavailable(Self.failure(from: nsError))
        }
        return .available
    }

    func evaluateBiometrics(reason: String) async -> BiometricGateEvaluationResult {
        let ctx = LAContext()
        return await evaluate(ctx, policy: .deviceOwnerAuthenticationWithBiometrics, reason: reason)
    }

    func evaluateDeviceOwnerAuthentication(reason: String) async -> BiometricGateEvaluationResult {
        let ctx = LAContext()
        return await evaluate(ctx, policy: .deviceOwnerAuthentication, reason: reason)
    }

    private func evaluate(
        _ ctx: LAContext,
        policy: LAPolicy,
        reason: String
    ) async -> BiometricGateEvaluationResult {
        await withCheckedContinuation { continuation in
            ctx.evaluatePolicy(policy, localizedReason: reason) { success, error in
                if success {
                    continuation.resume(returning: .success)
                } else {
                    continuation.resume(returning: .failure(Self.failure(from: error)))
                }
            }
        }
    }

    private static func failure(from error: (any Error)?) -> BiometricGateAuthFailure {
        if let laError = error as? LAError {
            return BiometricGateAuthFailure(
                code: laError.code,
                reason: laError.localizedDescription
            )
        }
        return BiometricGateAuthFailure(
            code: nil,
            reason: error?.localizedDescription ?? "Authentication failed"
        )
    }
}
