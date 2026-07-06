import LocalAuthentication
import Testing
import LancerCore
@testable import SecurityKit

@Suite("BiometricGate")
struct BiometricGateTests {

    @Test("passcode-not-set preflight fails closed")
    func passcodeNotSetPreflightFailsClosed() async {
        let gate = BiometricGate(authenticator: StubAuthenticator(
            biometricAvailability: .unavailable(.init(
                code: .passcodeNotSet,
                reason: "Passcode is not set."
            ))
        ))

        await #expect(throws: LancerError.authFailed(reason: "Passcode is not set.")) {
            try await gate.unlock(reason: "Authenticate")
        }
    }

    @Test("biometry unavailable preflight fails closed")
    func biometryUnavailablePreflightFailsClosed() async {
        let gate = BiometricGate(authenticator: StubAuthenticator(
            biometricAvailability: .unavailable(.init(
                code: .biometryNotAvailable,
                reason: "Biometry is not available."
            ))
        ))

        await #expect(throws: LancerError.authFailed(reason: "Biometry is not available.")) {
            try await gate.unlock(reason: "Authenticate")
        }
    }

    @Test("biometry not enrolled falls back to passcode")
    func biometryNotEnrolledFallsBackToPasscode() async throws {
        let authenticator = StubAuthenticator(
            biometricAvailability: .unavailable(.init(
                code: .biometryNotEnrolled,
                reason: "Biometry is not enrolled."
            )),
            passcodeResult: .success
        )
        let gate = BiometricGate(authenticator: authenticator)

        try await gate.unlock(reason: "Authenticate")
        #expect(await authenticator.passcodeEvaluationCount == 1)
    }
}

private actor StubAuthenticator: BiometricGateAuthenticating {
    let biometricAvailability: BiometricGateAvailability
    let biometricResult: BiometricGateEvaluationResult
    let passcodeResult: BiometricGateEvaluationResult
    private(set) var passcodeEvaluationCount = 0

    init(
        biometricAvailability: BiometricGateAvailability,
        biometricResult: BiometricGateEvaluationResult = .success,
        passcodeResult: BiometricGateEvaluationResult = .success
    ) {
        self.biometricAvailability = biometricAvailability
        self.biometricResult = biometricResult
        self.passcodeResult = passcodeResult
    }

    func canEvaluateBiometrics() async -> BiometricGateAvailability {
        biometricAvailability
    }

    func evaluateBiometrics(reason: String) async -> BiometricGateEvaluationResult {
        biometricResult
    }

    func evaluateDeviceOwnerAuthentication(reason: String) async -> BiometricGateEvaluationResult {
        passcodeEvaluationCount += 1
        return passcodeResult
    }
}
