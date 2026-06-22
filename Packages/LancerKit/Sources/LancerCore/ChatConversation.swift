import Foundation

public struct ChatConversation: Codable, Sendable, Identifiable {
    public let id: String
    public var title: String
    public var agentID: String
    public var vendor: String?
    public var hostName: String
    public var hostID: String?
    public var cwd: String
    public var model: String?
    public var budgetUSD: Double?
    public var status: Status
    public var createdAt: Date
    public var updatedAt: Date
    public var lastActivityAt: Date

    public enum Status: String, Codable, Sendable {
        case active
        case completed
        case failed
    }

    public init(
        id: String = UUID().uuidString,
        title: String,
        agentID: String,
        vendor: String? = nil,
        hostName: String,
        hostID: String? = nil,
        cwd: String,
        model: String? = nil,
        budgetUSD: Double? = nil,
        status: Status = .active,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        lastActivityAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.agentID = agentID
        self.vendor = vendor
        self.hostName = hostName
        self.hostID = hostID
        self.cwd = cwd
        self.model = model
        self.budgetUSD = budgetUSD
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastActivityAt = lastActivityAt
    }
}

public struct ChatTurn: Codable, Sendable, Identifiable {
    public let id: String
    public let conversationID: String
    public let ordinal: Int
    public let prompt: String
    public let runID: String
    public let transportKind: String
    public var status: Status
    public var assistantText: String
    public var errorMessage: String?
    public var createdAt: Date
    public var completedAt: Date?

    public enum Status: String, Codable, Sendable {
        case running
        case completed
        case failed
    }

    public init(
        id: String = UUID().uuidString,
        conversationID: String,
        ordinal: Int,
        prompt: String,
        runID: String,
        transportKind: String = "ssh",
        status: Status = .running,
        assistantText: String = "",
        errorMessage: String? = nil,
        createdAt: Date = .now,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.conversationID = conversationID
        self.ordinal = ordinal
        self.prompt = prompt
        self.runID = runID
        self.transportKind = transportKind
        self.status = status
        self.assistantText = assistantText
        self.errorMessage = errorMessage
        self.createdAt = createdAt
        self.completedAt = completedAt
    }
}

public struct ChatArtifact: Codable, Sendable, Identifiable {
    public let id: String
    public let conversationID: String
    public let turnID: String
    public let runID: String
    public let kind: Kind
    public var title: String
    public var summary: String?
    public var payloadJSON: String
    public var status: Status
    public var createdAt: Date
    public var updatedAt: Date

    public enum Kind: String, Codable, Sendable {
        case tool
        case diff
        case file
        case test
        case preview
        case approval
    }

    public enum Status: String, Codable, Sendable {
        case running
        case done
        case failed
    }

    public init(
        id: String = UUID().uuidString,
        conversationID: String,
        turnID: String,
        runID: String,
        kind: Kind,
        title: String,
        summary: String? = nil,
        payloadJSON: String = "{}",
        status: Status = .running,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.conversationID = conversationID
        self.turnID = turnID
        self.runID = runID
        self.kind = kind
        self.title = title
        self.summary = summary
        self.payloadJSON = payloadJSON
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct ChatConversationSearchResult: Sendable, Identifiable {
    public let conversation: ChatConversation
    public let snippet: String
    public var id: String { conversation.id }

    public init(conversation: ChatConversation, snippet: String) {
        self.conversation = conversation
        self.snippet = snippet
    }
}
