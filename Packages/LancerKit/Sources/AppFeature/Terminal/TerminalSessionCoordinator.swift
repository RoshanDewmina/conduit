#if os(iOS)
import Foundation
import Observation
import LancerCore
import SecurityKit
import SSHTransport
import PersistenceKit
import SessionFeature

/// Presentation state for the interactive SSH terminal (Phase 1).
@MainActor @Observable
public final class TerminalSessionCoordinator {
    public struct PasswordPromptHost: Identifiable, Equatable {
        public let id: HostID
        public let host: Host
        public let startupCommand: String?

        public init(host: Host, startupCommand: String?) {
            self.id = host.id
            self.host = host
            self.startupCommand = startupCommand
        }
    }

    public private(set) var presentedModel: LiveTerminalModel?
    public var passwordPromptHost: PasswordPromptHost?
    public var lastErrorMessage: String?

    private let hostRepo: HostRepository
    private let keyStore: KeyStore
    private let hostKeyStore: HostKeyStore
    /// Session-only passwords (not persisted to Keychain).
    private var sessionPasswords: [HostID: String] = [:]

    public init(hostRepo: HostRepository, keyStore: KeyStore, hostKeyStore: HostKeyStore) {
        self.hostRepo = hostRepo
        self.keyStore = keyStore
        self.hostKeyStore = hostKeyStore
    }

    public func openTerminal(host: Host, startupCommand: String?) {
        lastErrorMessage = nil
        switch host.authMethod {
        case .password:
            if let password = sessionPasswords[host.id] {
                presentModel(host: host, password: password, startupCommand: startupCommand)
            } else {
                passwordPromptHost = PasswordPromptHost(host: host, startupCommand: startupCommand)
            }
        case .ed25519:
            presentModel(host: host, credentialProvider: { [keyStore] in
                try await CredentialResolver.resolve(
                    authMethod: host.authMethod,
                    passwordProvider: { throw LancerError.authFailed(reason: "password not configured") },
                    keyStore: keyStore
                )
            }, startupCommand: startupCommand)
        case .agent:
            lastErrorMessage = "SSH agent forwarding is not supported yet."
        }
    }

    public func presentPasswordThenOpen(host: Host, password: String, startupCommand: String?) {
        sessionPasswords[host.id] = password
        passwordPromptHost = nil
        presentModel(host: host, password: password, startupCommand: startupCommand)
    }

    public func dismissTerminal() {
        presentedModel?.stop()
        presentedModel = nil
    }

    public func cancelPasswordPrompt() {
        passwordPromptHost = nil
    }

    public func allHosts() async throws -> [Host] {
        try await hostRepo.all()
    }

    /// DEBUG / harness: open terminal for the first saved host.
    public func openFirstHostIfAvailable() async {
        guard let host = try? await hostRepo.all().first else { return }
        openTerminal(host: host, startupCommand: nil)
    }

    /// Remember a password for this session and open the terminal immediately.
    public func openWithSessionPassword(host: Host, password: String, startupCommand: String?) {
        sessionPasswords[host.id] = password
        openTerminal(host: host, startupCommand: startupCommand)
    }

    public func saveHostAndOpen(_ host: Host, password: String, startupCommand: String?) async {
        do {
            try await hostRepo.upsert(host)
            openWithSessionPassword(host: host, password: password, startupCommand: startupCommand)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    // MARK: - Private

    private func presentModel(host: Host, password: String, startupCommand: String?) {
        presentModel(host: host, credentialProvider: { .password(password) }, startupCommand: startupCommand)
    }

    private func presentModel(
        host: Host,
        credentialProvider: @escaping @Sendable () async throws -> SSHCredential,
        startupCommand: String?
    ) {
        presentedModel = LiveTerminalModel(
            host: host,
            credentialProvider: credentialProvider,
            hostKeyStore: hostKeyStore,
            autoCommand: startupCommand
        )
    }
}
#endif
