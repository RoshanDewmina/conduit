import Foundation

/// Live bridge RPC actions from an active fleet SSH session (policy, audit, dispatch).
public struct BridgeSessionActions: Sendable {
    public var isConnected: Bool
    public var policyCWD: String
    public var loadPolicyYAML: @Sendable () async throws -> String
    public var savePolicyYAML: @Sendable (String) async throws -> Void
    public var reloadPolicy: @Sendable () async throws -> Void
    public var tailAudit: @Sendable (Int) async throws -> [AuditLogEntry]
    public var dispatch: @Sendable (String, String, String) async throws -> DispatchResult

    public init(
        isConnected: Bool = false,
        policyCWD: String = "~",
        loadPolicyYAML: @escaping @Sendable () async throws -> String = { throw BridgeSessionError.noChannel },
        savePolicyYAML: @escaping @Sendable (String) async throws -> Void = { _ in throw BridgeSessionError.noChannel },
        reloadPolicy: @escaping @Sendable () async throws -> Void = { throw BridgeSessionError.noChannel },
        tailAudit: @escaping @Sendable (Int) async throws -> [AuditLogEntry] = { _ in throw BridgeSessionError.noChannel },
        dispatch: @escaping @Sendable (String, String, String) async throws -> DispatchResult = { _, _, _ in
            throw BridgeSessionError.noChannel
        }
    ) {
        self.isConnected = isConnected
        self.policyCWD = policyCWD
        self.loadPolicyYAML = loadPolicyYAML
        self.savePolicyYAML = savePolicyYAML
        self.reloadPolicy = reloadPolicy
        self.tailAudit = tailAudit
        self.dispatch = dispatch
    }
}

public enum BridgeSessionError: Error, Sendable, LocalizedError {
    case noChannel

    public var errorDescription: String? {
        switch self {
        case .noChannel: "Connect an SSH host session first."
        }
    }
}
