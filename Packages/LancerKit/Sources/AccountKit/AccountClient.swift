import Foundation
import Observation
import SecurityKit
import CryptoKit
#if canImport(DeviceCheck)
import DeviceCheck
#endif

/// Deliberately small account boundary for the iOS app. The UI depends on this
/// protocol, never directly on Supabase, so previews and tests do not need a
/// network project or credentials.
public protocol AccountClient: Sendable {
    func signUp(email: String, password: String) async throws -> AccountSignUpResult
    /// Sign up carrying the user's display name (stored in the account's
    /// `user_metadata.name`). A protocol requirement with a default below, so
    /// existing conformers (tests/mocks) keep working while Supabase overrides it.
    func signUp(name: String, email: String, password: String) async throws -> AccountSignUpResult
    func signIn(email: String, password: String) async throws -> AccountSession
    func restoreSession(_ session: AccountSession) async throws -> AccountSession
    func requestPasswordReset(email: String, redirectURL: URL) async throws
    func completePasswordReset(callbackURL: URL, newPassword: String) async throws -> AccountSession
}

public extension AccountClient {
    // Default: ignore the name (offline/mock/test conformers). SupabaseAccountClient
    // overrides this to persist it into user_metadata.
    func signUp(name: String, email: String, password: String) async throws -> AccountSignUpResult {
        try await signUp(email: email, password: password)
    }
}

public enum AccountMode: String, Codable, Sendable, Equatable {
    case standard
    case selfHostedOffline
}

public struct AccountSession: Codable, Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date
    public let userID: String
    public let email: String

    public init(accessToken: String, refreshToken: String, expiresAt: Date, userID: String, email: String) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.userID = userID
        self.email = email
    }
}

public struct AccountSignUpResult: Sendable, Equatable {
    public let session: AccountSession?
    public let confirmationRequired: Bool

    public init(session: AccountSession?, confirmationRequired: Bool) {
        self.session = session
        self.confirmationRequired = confirmationRequired
    }
}

/// A daemon device bound to the account. Timestamps stay as the backend's
/// RFC3339 strings so decoding never fails on Go's fractional-second format;
/// `status` is derived from which timestamps are present.
public struct BoundDevice: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let publicFingerprint: String
    public let expiresAt: String?
    public let boundAt: String?
    public let redeemedAt: String?
    public let revokedAt: String?

    public init(id: String, name: String, publicFingerprint: String, expiresAt: String?, boundAt: String?, redeemedAt: String?, revokedAt: String?) {
        self.id = id
        self.name = name
        self.publicFingerprint = publicFingerprint
        self.expiresAt = expiresAt
        self.boundAt = boundAt
        self.redeemedAt = redeemedAt
        self.revokedAt = revokedAt
    }

    public enum Status: String, Sendable, Equatable {
        case active        // redeemed by a daemon and live
        case awaitingDaemon // approved on phone, daemon has not redeemed yet
        case pending       // challenge created, not yet approved
        case expired       // challenge lapsed before redemption
        case revoked
    }

    public func status(now: Date = .now) -> Status {
        if revokedAt?.isEmpty == false { return .revoked }
        if redeemedAt?.isEmpty == false { return .active }
        if let expiresAt, let date = BoundDevice.parseDate(expiresAt), date < now { return .expired }
        if boundAt?.isEmpty == false { return .awaitingDaemon }
        return .pending
    }

    public static func decodeList(_ data: Data) throws -> [BoundDevice] {
        try JSONDecoder().decode([BoundDevice].self, from: data)
    }

    public static func parseDate(_ string: String) -> Date? {
        for formatter in formatters {
            if let date = formatter.date(from: string) { return date }
        }
        return nil
    }

    nonisolated(unsafe) private static let formatters: [ISO8601DateFormatter] = {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return [withFraction, plain]
    }()
}

public enum AccountError: LocalizedError, Sendable, Equatable {
    case unavailable
    case invalidCredentials
    case passwordTooShort
    case invalidCallback
    case noAuthenticatedSession
    case expiredSession
    case requestFailed(status: Int)
    case malformedResponse

    public var errorDescription: String? {
        switch self {
        case .unavailable: "Account service is not configured on this build."
        case .invalidCredentials: "We couldn't sign you in with those details."
        case .passwordTooShort: "Use at least 12 characters for your password."
        case .invalidCallback: "That account link is incomplete or has expired."
        case .noAuthenticatedSession: "Sign in before binding a device."
        case .expiredSession: "Your session expired. Please sign in again."
        case .requestFailed: "The account service is unavailable. Try again shortly."
        case .malformedResponse: "The account service sent an unexpected response."
        }
    }
}

public struct AccountConfiguration: Sendable, Equatable {
    public let supabaseURL: URL?
    public let publishableKey: String?

    public init(supabaseURL: URL?, publishableKey: String?) {
        self.supabaseURL = supabaseURL
        self.publishableKey = publishableKey
    }

    /// Values are build configuration, not secrets. The service role and SMTP
    /// credentials stay server-side. Empty values intentionally leave standard
    /// sign-in unavailable while self-hosted offline remains usable.
    public static func fromBundle(_ bundle: Bundle = .main) -> Self {
        let urlString = bundle.object(forInfoDictionaryKey: "LANCER_SUPABASE_URL") as? String
        let key = bundle.object(forInfoDictionaryKey: "LANCER_SUPABASE_PUBLISHABLE_KEY") as? String
        return Self(
            supabaseURL: urlString.flatMap { $0.hasPrefix("$(") ? nil : URL(string: $0) },
            publishableKey: key?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty.flatMap { $0.hasPrefix("$(") ? nil : $0 }
        )
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

public extension Notification.Name {
    static let lancerAuthCallback = Notification.Name("lancerAuthCallback")
}

/// Keychain persistence is device-only and deliberately contains only the
/// Supabase session. A daemon never sees this material or the account password.
public actor AccountSessionStore {
    private let keychain: Keychain
    private let account = "session"
    private let modeKey: String

    public init(
        keychain: Keychain = Keychain(service: "dev.lancer.mobile.account"),
        modeStorageKey: String = "dev.lancer.account.mode"
    ) {
        self.keychain = keychain
        self.modeKey = modeStorageKey
    }

    public func loadSession() async throws -> AccountSession? {
        guard let data = try? await keychain.read(account: account) else { return nil }
        return try JSONDecoder().decode(AccountSession.self, from: data)
    }

    public func save(_ session: AccountSession) async throws {
        let data = try JSONEncoder().encode(session)
        try await keychain.write(data, account: account, accessibility: .afterFirstUnlockThisDeviceOnly)
        UserDefaults.standard.set(AccountMode.standard.rawValue, forKey: modeKey)
    }

    public func setOfflineMode() {
        UserDefaults.standard.set(AccountMode.selfHostedOffline.rawValue, forKey: modeKey)
    }

    public func mode() -> AccountMode? {
        UserDefaults.standard.string(forKey: modeKey).flatMap(AccountMode.init(rawValue:))
    }

    public func clear() async throws {
        try await keychain.delete(account: account)
        UserDefaults.standard.removeObject(forKey: modeKey)
    }
}

/// App-owned observable state. Keep account lifecycle here so iOS 27 state
/// initialization has one durable owner rather than reinitializing in views.
@MainActor @Observable
public final class AccountSessionController {
    public private(set) var mode: AccountMode?
    public private(set) var session: AccountSession?
    public private(set) var isRestoring = false

    private let client: any AccountClient
    private let store: AccountSessionStore
    private let urlSession: URLSession

    public init(client: any AccountClient, store: AccountSessionStore = AccountSessionStore(), urlSession: URLSession = .shared) {
        self.client = client
        self.store = store
        self.urlSession = urlSession
    }

    public var email: String? { session?.email }
    public var isStandardAccount: Bool { mode == .standard && session != nil }
    public var isOfflineSelfHosted: Bool { mode == .selfHostedOffline }

    /// The user's display name, captured during onboarding and used to personalize
    /// the app (sidebar, settings). Persisted locally so it works for both standard
    /// accounts and offline self-hosted users, independent of any network session.
    private static let displayNameKey = "lancer.account.displayName"
    public var displayName: String? {
        let v = UserDefaults.standard.string(forKey: Self.displayNameKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (v?.isEmpty == false) ? v : nil
    }
    public static var storedDisplayName: String? {
        let v = UserDefaults.standard.string(forKey: displayNameKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (v?.isEmpty == false) ? v : nil
    }
    private func persistDisplayName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        UserDefaults.standard.set(trimmed, forKey: Self.displayNameKey)
    }

    public func restore() async {
        guard !isRestoring else { return }
        isRestoring = true
        defer { isRestoring = false }
        mode = await store.mode()
        guard mode == .standard, let saved = try? await store.loadSession() else { return }
        do {
            let restored = try await client.restoreSession(saved)
            try await store.save(restored)
            session = restored
        } catch {
            try? await store.clear()
            mode = nil
            session = nil
        }
    }

    public func signUp(email: String, password: String) async throws -> AccountSignUpResult {
        try await signUp(name: "", email: email, password: password)
    }

    public func signUp(name: String, email: String, password: String) async throws -> AccountSignUpResult {
        guard password.count >= 12 else { throw AccountError.passwordTooShort }
        // Persist the name locally first so the app can personalize immediately,
        // even when sign-up requires email confirmation before a session exists.
        persistDisplayName(name)
        let result = try await client.signUp(name: name, email: email, password: password)
        if let session = result.session {
            try await store.save(session)
            self.session = session
            self.mode = .standard
        }
        return result
    }

    public func signIn(email: String, password: String) async throws {
        guard password.count >= 12 else { throw AccountError.invalidCredentials }
        do {
            let session = try await client.signIn(email: email, password: password)
            try await store.save(session)
            self.session = session
            self.mode = .standard
        } catch AccountError.unavailable {
            // A build with no Supabase configuration must say so; presenting it
            // as a bad password makes the recovery path needlessly confusing.
            throw AccountError.unavailable
        } catch AccountError.requestFailed(let status) {
            throw AccountError.requestFailed(status: status)
        } catch AccountError.invalidCredentials {
            throw AccountError.invalidCredentials // preserve neutral wording
        } catch {
            throw AccountError.invalidCredentials
        }
    }

    public func useSelfHostedOffline(name: String = "") async {
        persistDisplayName(name)
        try? await store.clear()
        await store.setOfflineMode()
        session = nil
        mode = .selfHostedOffline
    }

    public func requestPasswordReset(email: String) async throws {
        try await client.requestPasswordReset(email: email, redirectURL: URL(string: "lancer://auth/callback")!)
    }

    public func completePasswordReset(callbackURL: URL, newPassword: String) async throws {
        guard newPassword.count >= 12 else { throw AccountError.passwordTooShort }
        let session = try await client.completePasswordReset(callbackURL: callbackURL, newPassword: newPassword)
        try await store.save(session)
        self.session = session
        self.mode = .standard
    }

    public func signOut() async {
        try? await store.clear()
        mode = nil
        session = nil
    }

    /// Authorizes a daemon challenge after the phone scanned its QR. The only
    /// credential sent is the user's existing access token; neither the phone
    /// nor the daemon sends an account password. On hardware that supports App
    /// Attest the request also carries a fresh attestation over a server nonce,
    /// which production backends REQUIRE — a leaked QR secret plus a signed-in
    /// session is deliberately not sufficient to bind on its own.
    public func bindDaemonDevice(challengeID: String, secret: String, backendURL: URL) async throws {
        guard let session else { throw AccountError.noAuthenticatedSession }
        let base = backendURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + "/v1/devices/bind") else { throw AccountError.malformedResponse }
        // Simulator / unsupported hardware yields nil and the bind proceeds
        // bare — accepted only by a backend running with App Attest disabled
        // (local dev); a production backend rejects it with 401.
        let attestation = try await mintAppAttestation(base: base, accessToken: session.accessToken)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(DeviceBindPayload(
            challengeID: challengeID,
            secret: secret,
            attestChallengeId: attestation?.challengeID,
            attestKeyId: attestation?.keyID,
            attestationObject: attestation?.object
        ))
        let (_, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AccountError.requestFailed(status: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }

    /// Generates an App Attest key and attests it over a server-minted nonce.
    /// Returns nil where App Attest is unavailable (simulator, macOS test host).
    private func mintAppAttestation(base: String, accessToken: String) async throws -> MintedAppAttestation? {
        #if canImport(DeviceCheck)
        let service = DCAppAttestService.shared
        guard service.isSupported else { return nil }
        guard let url = URL(string: base + "/v1/devices/attest-challenge") else { throw AccountError.malformedResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AccountError.requestFailed(status: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        struct AttestChallengeResponse: Decodable { let attestChallengeId: String; let challenge: String }
        guard let minted = try? JSONDecoder().decode(AttestChallengeResponse.self, from: data),
              let challengeData = Data(base64Encoded: minted.challenge)
        else { throw AccountError.malformedResponse }
        let keyID = try await service.generateKey()
        let clientDataHash = Data(SHA256.hash(data: challengeData))
        let attestation = try await service.attestKey(keyID, clientDataHash: clientDataHash)
        return MintedAppAttestation(
            challengeID: minted.attestChallengeId,
            keyID: keyID,
            object: attestation.base64EncodedString()
        )
        #else
        return nil
        #endif
    }

    /// Lists the daemon devices bound to this account. Offline self-hosted mode
    /// has no account-scoped device list, so it requires a standard session.
    public func listDevices(backendURL: URL) async throws -> [BoundDevice] {
        guard let session else { throw AccountError.noAuthenticatedSession }
        let base = backendURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + "/v1/devices") else { throw AccountError.malformedResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AccountError.requestFailed(status: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try BoundDevice.decodeList(data)
    }

    /// Revokes a bound daemon device. The backend clears the device credential
    /// hash so the daemon can no longer redeem the capability.
    public func revokeDevice(id: String, backendURL: URL) async throws {
        guard let session else { throw AccountError.noAuthenticatedSession }
        let base = backendURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: base + "/v1/devices/" + encoded + "/revoke") else { throw AccountError.malformedResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AccountError.requestFailed(status: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }
}

public struct SupabaseAccountClient: AccountClient {
    private let configuration: AccountConfiguration
    private let session: URLSession

    public init(configuration: AccountConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    public func signUp(email: String, password: String) async throws -> AccountSignUpResult {
        try await signUp(name: "", email: email, password: password)
    }

    public func signUp(name: String, email: String, password: String) async throws -> AccountSignUpResult {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let response: AuthResponse = try await request(
            path: "signup",
            method: "POST",
            body: SignUpBody(
                email: email,
                password: password,
                data: trimmed.isEmpty ? nil : SignUpMetadata(name: trimmed)
            )
        )
        let session = response.session.map(AccountSession.init)
        return AccountSignUpResult(session: session, confirmationRequired: session == nil)
    }

    public func signIn(email: String, password: String) async throws -> AccountSession {
        let response: AuthResponse = try await request(
            path: "token?grant_type=password",
            method: "POST",
            body: ["email": email, "password": password]
        )
        guard let session = response.session.map(AccountSession.init) else { throw AccountError.invalidCredentials }
        return session
    }

    public func restoreSession(_ session: AccountSession) async throws -> AccountSession {
        if session.expiresAt > Date().addingTimeInterval(60) { return session }
        let response: AuthResponse = try await request(
            path: "token?grant_type=refresh_token",
            method: "POST",
            body: ["refresh_token": session.refreshToken]
        )
        guard let refreshed = response.session.map(AccountSession.init) else { throw AccountError.expiredSession }
        return refreshed
    }

    public func requestPasswordReset(email: String, redirectURL: URL) async throws {
        let _: EmptyResponse = try await request(
            path: "recover",
            method: "POST",
            body: ["email": email, "redirect_to": redirectURL.absoluteString]
        )
    }

    public func completePasswordReset(callbackURL: URL, newPassword: String) async throws -> AccountSession {
        let token = try callbackToken(callbackURL)
        let request = try makeRequest(path: "user", method: "PUT", body: ["password": newPassword])
        var authenticated = request
        authenticated.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: authenticated)
        guard let http = response as? HTTPURLResponse else { throw AccountError.malformedResponse }
        guard (200..<300).contains(http.statusCode) else { throw AccountError.invalidCallback }
        let user = try JSONDecoder().decode(AuthUser.self, from: data)
        return AccountSession(accessToken: token.accessToken, refreshToken: token.refreshToken, expiresAt: token.expiresAt, userID: user.id, email: user.email)
    }

    private func callbackToken(_ url: URL) throws -> CallbackToken {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let query = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).compactMap { item in item.value.map { (item.name, $0) } })
        let fragment = URLComponents(string: "?\(components?.fragment ?? "")")
        let fragmentItems = Dictionary(uniqueKeysWithValues: (fragment?.queryItems ?? []).compactMap { item in item.value.map { (item.name, $0) } })
        let values = query.merging(fragmentItems) { _, latest in latest }
        guard let access = values["access_token"], let refresh = values["refresh_token"] else { throw AccountError.invalidCallback }
        let expiry = values["expires_in"].flatMap(TimeInterval.init).map { Date().addingTimeInterval($0) } ?? Date().addingTimeInterval(3600)
        return CallbackToken(accessToken: access, refreshToken: refresh, expiresAt: expiry)
    }

    private func request<Response: Decodable, Body: Encodable>(path: String, method: String, body: Body) async throws -> Response {
        let request = try makeRequest(path: path, method: method, body: body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AccountError.malformedResponse }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 400 || http.statusCode == 401 || http.statusCode == 422 { throw AccountError.invalidCredentials }
            throw AccountError.requestFailed(status: http.statusCode)
        }
        if Response.self == EmptyResponse.self { return EmptyResponse() as! Response }
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func makeRequest<Body: Encodable>(path: String, method: String, body: Body) throws -> URLRequest {
        guard let base = configuration.supabaseURL, let key = configuration.publishableKey,
              let url = URL(string: "auth/v1/\(path)", relativeTo: base) else { throw AccountError.unavailable }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue(key, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }
}

private struct EmptyResponse: Decodable {}
private struct SignUpMetadata: Encodable { let name: String }
private struct SignUpBody: Encodable {
    let email: String
    let password: String
    // Supabase GoTrue stores `data` into the user's user_metadata at sign-up.
    var data: SignUpMetadata? = nil
}
private struct DeviceBindPayload: Encodable {
    let challengeID: String
    let secret: String
    var attestChallengeId: String? = nil
    var attestKeyId: String? = nil
    var attestationObject: String? = nil
}

private struct MintedAppAttestation {
    let challengeID: String
    let keyID: String
    let object: String
}
private struct CallbackToken { let accessToken: String; let refreshToken: String; let expiresAt: Date }
private struct AuthUser: Decodable { let id: String; let email: String }
private struct AuthResponse: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: TimeInterval?
    let user: AuthUser?

    enum CodingKeys: String, CodingKey { case accessToken = "access_token", refreshToken = "refresh_token", expiresIn = "expires_in", user }

    var session: AuthSessionPayload? {
        guard let accessToken, let refreshToken, let user else { return nil }
        return AuthSessionPayload(accessToken: accessToken, refreshToken: refreshToken, expiresIn: expiresIn ?? 3600, user: user)
    }
}
private struct AuthSessionPayload {
    let accessToken: String
    let refreshToken: String
    let expiresIn: TimeInterval
    let user: AuthUser
}
private extension AccountSession {
    init(_ payload: AuthSessionPayload) {
        self.init(accessToken: payload.accessToken, refreshToken: payload.refreshToken, expiresAt: Date().addingTimeInterval(payload.expiresIn), userID: payload.user.id, email: payload.user.email)
    }
}
