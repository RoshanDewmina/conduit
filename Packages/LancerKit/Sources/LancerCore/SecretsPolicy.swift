import Foundation

/// A credential request from an agent seeking access to a secret.
public struct SecretRequest: Sendable, Codable, Identifiable {
    public let id: String
    public let agent: String
    public let toolName: String
    public let credentialType: CredentialType
    public let requestedScope: String
    public let hostID: String
    public let timestamp: Date

    public enum CredentialType: String, Codable, Sendable {
        case apiKey
        case sshKey
        case token
        case password
        case oauth
    }

    public init(
        id: String = UUID().uuidString,
        agent: String,
        toolName: String,
        credentialType: CredentialType,
        requestedScope: String,
        hostID: String,
        timestamp: Date = .now
    ) {
        self.id = id
        self.agent = agent
        self.toolName = toolName
        self.credentialType = credentialType
        self.requestedScope = requestedScope
        self.hostID = hostID
        self.timestamp = timestamp
    }
}

/// A scoped authorization for a secret.
public struct SecretAuthorization: Sendable, Codable {
    public let requestID: String
    public let scope: String
    public let expiresAt: Date?
    public let oneTimeUse: Bool
    public let allowedBy: String

    public init(
        requestID: String,
        scope: String,
        expiresAt: Date? = nil,
        oneTimeUse: Bool = false,
        allowedBy: String = "user"
    ) {
        self.requestID = requestID
        self.scope = scope
        self.expiresAt = expiresAt
        self.oneTimeUse = oneTimeUse
        self.allowedBy = allowedBy
    }
}

/// Stored secret entry on the daemon (metadata only — the raw value never leaves the daemon).
public struct SecretEntry: Sendable, Codable, Identifiable {
    public let id: String
    public let name: String
    public let type: SecretRequest.CredentialType
    public let scope: String
    public let addedAt: Date
    public let lastUsedAt: Date?
    public let useCount: Int

    public init(
        id: String,
        name: String,
        type: SecretRequest.CredentialType,
        scope: String,
        addedAt: Date,
        lastUsedAt: Date? = nil,
        useCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.scope = scope
        self.addedAt = addedAt
        self.lastUsedAt = lastUsedAt
        self.useCount = useCount
    }
}

/// Pending secret request awaiting phone authorization.
public struct PendingSecretRequest: Sendable, Codable, Identifiable {
    public let id: String
    public let request: SecretRequest
    public let receivedAt: Date

    public init(id: String = UUID().uuidString, request: SecretRequest, receivedAt: Date = .now) {
        self.id = id
        self.request = request
        self.receivedAt = receivedAt
    }
}
