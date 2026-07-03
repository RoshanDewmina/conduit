import Foundation

/// Privacy-safe Spotlight field builders for App Intents indexing.
/// Kept in PersistenceKit so unit tests can assert no secrets leak into indexes.
public enum IntentEntitySpotlightSupport {
    public static let spotlightDomain = "dev.lancer.mobile"

    public struct ConversationIndexFields: Sendable, Equatable {
        public let identifier: String
        public let title: String
        public let hostName: String
        public let vendorLabel: String?
        public let workspaceFolderName: String
        public let lastActivityAt: Date

        public init(_ record: IntentConversationRecord) {
            identifier = record.id
            title = record.title
            hostName = record.hostName
            vendorLabel = record.vendor
            workspaceFolderName = URL(fileURLWithPath: record.workspacePath).lastPathComponent
            lastActivityAt = record.lastActivityAt
        }
    }

    public struct MachineIndexFields: Sendable, Equatable {
        public let identifier: String
        public let displayName: String
        public let connectivityLabel: String

        public init(_ record: IntentMachineRecord, connectivityLabel: String) {
            identifier = record.id
            displayName = record.displayName
            self.connectivityLabel = connectivityLabel
        }
    }

    public struct WorkspaceIndexFields: Sendable, Equatable {
        public let identifier: String
        public let name: String
        public let folderName: String

        public init(_ record: IntentWorkspaceRecord) {
            identifier = record.id
            name = record.name
            folderName = URL(fileURLWithPath: record.path).lastPathComponent
        }
    }

    public struct RunIndexFields: Sendable, Equatable {
        public let identifier: String
        public let title: String
        public let hostName: String?
        public let status: String

        public init(_ record: IntentRunRecord) {
            identifier = record.id
            title = record.conversationTitle ?? record.title
            hostName = record.hostName
            status = record.status
        }
    }

    public struct ApprovalIndexFields: Sendable, Equatable {
        public let identifier: String
        public let headline: String
        public let riskLabel: String
        public let agentLabel: String
        public let createdAt: Date

        public init(_ record: IntentApprovalRecord) {
            identifier = record.id
            headline = record.headline
            riskLabel = record.riskLabel
            agentLabel = record.agentLabel
            createdAt = record.createdAt
        }
    }

    /// Returns `true` when the serialized index payload would include a forbidden field.
    public static func containsForbiddenIndexMaterial(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let forbidden = [
            "api_key", "apikey", "secret", "password", "token", "bearer ",
            "private key", "ssh-rsa", "-----begin",
        ]
        return forbidden.contains { lowered.contains($0) }
    }

    /// Stable cross-device ID for conversations when sync metadata is present.
    public static func syncableConversationStableID(
        conversationID: String,
        cloudRecordName: String?
    ) -> String {
        cloudRecordName ?? conversationID
    }

    public static func stableMachineID(_ record: IntentMachineRecord) -> String { record.id }
    public static func stableWorkspaceID(_ record: IntentWorkspaceRecord) -> String { record.id }
}
