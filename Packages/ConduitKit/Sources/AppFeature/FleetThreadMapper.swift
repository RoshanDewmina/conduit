import Foundation
import ConduitCore
import PersistenceKit

@MainActor
public struct FleetThreadMapper {
    public static func findConversation(
        hostName: String,
        agentID: String,
        cwd: String,
        chatRepo: ChatConversationRepository
    ) async -> ChatConversation? {
        let recent = try? await chatRepo.recent(limit: 100)
        return recent?.first { conv in
            conv.hostName == hostName
                && conv.agentID == agentID
                && conv.cwd == cwd
                && conv.status == .active
        }
    }

    public struct FleetRow: Identifiable, Sendable {
        public let id: UUID
        public let hostName: String
        public let agentID: String
        public let cwd: String
        public let status: String
        public let conversationID: String?
        public let hasPendingApprovals: Bool

        public init(
            id: UUID = UUID(),
            hostName: String,
            agentID: String,
            cwd: String,
            status: String,
            conversationID: String? = nil,
            hasPendingApprovals: Bool = false
        ) {
            self.id = id
            self.hostName = hostName
            self.agentID = agentID
            self.cwd = cwd
            self.status = status
            self.conversationID = conversationID
            self.hasPendingApprovals = hasPendingApprovals
        }
    }
}
