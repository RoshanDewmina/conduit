import Foundation
import Testing
@testable import AccountKit
@testable import SecurityKit

private struct AccountClientFixture: AccountClient {
    let session: AccountSession

    func signUp(email: String, password: String) async throws -> AccountSignUpResult {
        AccountSignUpResult(session: session, confirmationRequired: false)
    }
    func signIn(email: String, password: String) async throws -> AccountSession { session }
    func restoreSession(_ session: AccountSession) async throws -> AccountSession { self.session }
    func requestPasswordReset(email: String, redirectURL: URL) async throws {}
    func completePasswordReset(callbackURL: URL, newPassword: String) async throws -> AccountSession { session }
}

private struct UnavailableAccountClient: AccountClient {
    func signUp(email: String, password: String) async throws -> AccountSignUpResult { throw AccountError.unavailable }
    func signIn(email: String, password: String) async throws -> AccountSession { throw AccountError.unavailable }
    func restoreSession(_ session: AccountSession) async throws -> AccountSession { throw AccountError.unavailable }
    func requestPasswordReset(email: String, redirectURL: URL) async throws { throw AccountError.unavailable }
    func completePasswordReset(callbackURL: URL, newPassword: String) async throws -> AccountSession { throw AccountError.unavailable }
}

private actor ResetRequestRecorder {
    private var lastRedirect: URL?
    func record(_ redirect: URL) { lastRedirect = redirect }
    func redirect() -> URL? { lastRedirect }
}

private struct RecordingAccountClient: AccountClient {
    let session: AccountSession
    let recorder: ResetRequestRecorder

    func signUp(email: String, password: String) async throws -> AccountSignUpResult {
        AccountSignUpResult(session: session, confirmationRequired: false)
    }
    func signIn(email: String, password: String) async throws -> AccountSession { session }
    func restoreSession(_ session: AccountSession) async throws -> AccountSession { session }
    func requestPasswordReset(email: String, redirectURL: URL) async throws { await recorder.record(redirectURL) }
    func completePasswordReset(callbackURL: URL, newPassword: String) async throws -> AccountSession { session }
}

@Suite("Account session")
@MainActor
struct AccountSessionTests {
    private func makeStore() -> AccountSessionStore {
        AccountSessionStore(
            keychain: Keychain(service: UUID().uuidString, inMemory: true),
            modeStorageKey: "test.account.mode.\(UUID().uuidString)"
        )
    }

    private func makeSession() -> AccountSession {
        AccountSession(
            accessToken: "access", refreshToken: "refresh", expiresAt: .now.addingTimeInterval(3600),
            userID: "user-1", email: "person@example.com"
        )
    }

    @Test("offline self-hosted choice stores no account session")
    func offlineChoice() async {
        let store = makeStore()
        let controller = AccountSessionController(client: AccountClientFixture(session: makeSession()), store: store)
        await controller.useSelfHostedOffline()
        #expect(controller.isOfflineSelfHosted)
        #expect(controller.email == nil)
        #expect((try? await store.loadSession()) == nil)
    }

    @Test("standard account session restores from Keychain")
    func standardSessionRestores() async throws {
        let store = makeStore()
        let expected = makeSession()
        try await store.save(expected)
        let controller = AccountSessionController(client: AccountClientFixture(session: expected), store: store)
        await controller.restore()
        #expect(controller.isStandardAccount)
        #expect(controller.email == "person@example.com")
    }

    @Test("sign up rejects passwords shorter than twelve characters")
    func rejectsShortPassword() async {
        let controller = AccountSessionController(client: AccountClientFixture(session: makeSession()), store: makeStore())
        await #expect(throws: AccountError.passwordTooShort) {
            try await controller.signUp(email: "person@example.com", password: "short")
        }
    }

    @Test("password reset uses the Lancer deep-link and restores the returned session")
    func passwordResetDeepLink() async throws {
        let recorder = ResetRequestRecorder()
        let expected = makeSession()
        let store = makeStore()
        let controller = AccountSessionController(
            client: RecordingAccountClient(session: expected, recorder: recorder),
            store: store
        )

        try await controller.requestPasswordReset(email: expected.email)
        #expect(await recorder.redirect()?.absoluteString == "lancer://auth/callback")

        try await controller.completePasswordReset(
            callbackURL: URL(string: "lancer://auth/callback#access_token=token")!,
            newPassword: "twelve-or-more-characters"
        )
        #expect(controller.isStandardAccount)
        #expect((try await store.loadSession())?.email == expected.email)
    }

    @Test("sign out removes the durable session")
    func signOutClearsSession() async throws {
        let store = makeStore()
        let controller = AccountSessionController(client: AccountClientFixture(session: makeSession()), store: store)
        try await controller.signIn(email: "person@example.com", password: "twelve-or-more-characters")
        await controller.signOut()
        #expect(!controller.isStandardAccount)
        #expect((try await store.loadSession()) == nil)
    }

    @Test("unconfigured account service is not misreported as invalid credentials")
    func serviceConfigurationErrorIsPreserved() async {
        let controller = AccountSessionController(client: UnavailableAccountClient(), store: makeStore())
        await #expect(throws: AccountError.unavailable) {
            try await controller.signIn(email: "person@example.com", password: "twelve-or-more-characters")
        }
    }

    @Test("device management requires an authenticated session")
    func deviceManagementRequiresSession() async {
        let controller = AccountSessionController(client: AccountClientFixture(session: makeSession()), store: makeStore())
        let backend = URL(string: "https://example.com")!
        await #expect(throws: AccountError.noAuthenticatedSession) {
            _ = try await controller.listDevices(backendURL: backend)
        }
        await #expect(throws: AccountError.noAuthenticatedSession) {
            try await controller.revokeDevice(id: "d1", backendURL: backend)
        }
    }

    @Test("bound device decodes backend JSON and derives status, including fractional-second timestamps")
    func boundDeviceDecodesAndDerivesStatus() throws {
        let json = """
        [
          {"id":"d1","name":"hermes-box","publicFingerprint":"ABCDEF0123456789","expiresAt":"2999-01-01T00:00:00Z","boundAt":"2026-06-20T10:00:00Z","redeemedAt":"2026-06-20T10:05:00.123456Z"},
          {"id":"d2","name":"lapsed","publicFingerprint":"0011223344556677","expiresAt":"2000-01-01T00:00:00Z"},
          {"id":"d3","name":"gone","publicFingerprint":"AABBCCDDEEFF0011","expiresAt":"2999-01-01T00:00:00Z","boundAt":"2026-06-20T10:00:00Z","revokedAt":"2026-06-20T11:00:00Z"}
        ]
        """.data(using: .utf8)!
        let devices = try BoundDevice.decodeList(json)
        #expect(devices.count == 3)
        #expect(devices[0].status() == .active)   // redeemed (fractional seconds must parse)
        #expect(devices[1].status() == .expired)  // past expiry, never redeemed
        #expect(devices[2].status() == .revoked)
    }

    @Test("bound device is awaiting the daemon when approved but not yet redeemed")
    func boundDeviceAwaitsDaemon() {
        let device = BoundDevice(
            id: "x", name: "new", publicFingerprint: "f",
            expiresAt: nil, boundAt: "2026-06-20T10:00:00Z", redeemedAt: nil, revokedAt: nil
        )
        #expect(device.status() == .awaitingDaemon)
    }
}
