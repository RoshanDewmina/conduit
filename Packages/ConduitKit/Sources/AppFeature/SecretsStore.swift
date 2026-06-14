#if os(iOS)
import Foundation
import Observation
import ConduitCore
import SSHTransport

@MainActor @Observable
public final class SecretsStore {
    public var secrets: [SecretEntry] = []
    public var pendingRequests: [PendingSecretRequest] = []
    public var isLoading = false
    public var errorMessage: String?

    private var channel: DaemonChannel?

    public init() {}

    public func attach(channel: DaemonChannel) {
        self.channel = channel
    }

    public func load() async {
        guard let channel else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await channel.listSecrets()
            secrets = result.secrets ?? []
            pendingRequests = result.pending ?? []
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    public func storeSecret(name: String, type: String, scope: String, value: String) async -> Bool {
        guard let channel else { return false }
        do {
            _ = try await channel.storeSecret(name: name, type: type, scope: scope, value: value)
            await load()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    public func authorizeRequest(_ requestID: String, scope: String, oneTime: Bool = false) async {
        guard let channel else { return }
        do {
            _ = try await channel.authorizeSecret(requestID: requestID, scope: scope, oneTime: oneTime)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func revokeAuthorization(_ requestID: String) async {
        guard let channel else { return }
        do {
            _ = try await channel.revokeSecret(requestID: requestID)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func deleteSecret(_ secretID: String) async {
        guard let channel else { return }
        do {
            _ = try await channel.deleteSecret(secretID: secretID)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
#endif
