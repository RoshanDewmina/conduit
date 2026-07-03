import Foundation
import GRDB
import LancerCore

// MARK: - Snapshots (App Intents–agnostic, testable)

public struct IntentRelayMachineSnapshot: Sendable, Hashable {
    public let id: String
    public let displayName: String
    public let lastConnectedAt: Date?

    public init(id: String, displayName: String, lastConnectedAt: Date?) {
        self.id = id
        self.displayName = displayName
        self.lastConnectedAt = lastConnectedAt
    }
}

public struct IntentMachineRecord: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable {
        case sshHost
        case relayMachine
    }

    public let id: String
    public let displayName: String
    public let hostName: String
    public let kind: Kind
    public let lastConnectedAt: Date?

    public init(
        id: String,
        displayName: String,
        hostName: String,
        kind: Kind,
        lastConnectedAt: Date? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.hostName = hostName
        self.kind = kind
        self.lastConnectedAt = lastConnectedAt
    }
}

public struct IntentRunRecord: Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let conversationTitle: String?
    public let hostName: String?
    public let workspacePath: String?
    public let status: String

    public init(
        id: String,
        title: String,
        conversationTitle: String? = nil,
        hostName: String? = nil,
        workspacePath: String? = nil,
        status: String = "running"
    ) {
        self.id = id
        self.title = title
        self.conversationTitle = conversationTitle
        self.hostName = hostName
        self.workspacePath = workspacePath
        self.status = status
    }
}

public struct IntentApprovalRecord: Sendable, Hashable, Identifiable {
    public let id: String
    public let headline: String
    public let riskLabel: String
    public let hostName: String?
    public let workspacePath: String
    public let agentLabel: String
    public let createdAt: Date

    public init(
        id: String,
        headline: String,
        riskLabel: String,
        hostName: String?,
        workspacePath: String,
        agentLabel: String,
        createdAt: Date
    ) {
        self.id = id
        self.headline = headline
        self.riskLabel = riskLabel
        self.hostName = hostName
        self.workspacePath = workspacePath
        self.agentLabel = agentLabel
        self.createdAt = createdAt
    }
}

public struct IntentConversationRecord: Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let hostName: String
    public let workspacePath: String
    public let vendor: String?
    public let lastActivityAt: Date
    public let searchSnippet: String?

    public init(
        id: String,
        title: String,
        hostName: String,
        workspacePath: String,
        vendor: String? = nil,
        lastActivityAt: Date,
        searchSnippet: String? = nil
    ) {
        self.id = id
        self.title = title
        self.hostName = hostName
        self.workspacePath = workspacePath
        self.vendor = vendor
        self.lastActivityAt = lastActivityAt
        self.searchSnippet = searchSnippet
    }
}

public struct IntentWorkspaceRecord: Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let machineID: String
    public let path: String
    public let lastUsedAt: Date

    public init(id: String, name: String, machineID: String, path: String, lastUsedAt: Date) {
        self.id = id
        self.name = name
        self.machineID = machineID
        self.path = path
        self.lastUsedAt = lastUsedAt
    }
}

// MARK: - Matching

public enum IntentEntityMatcher {
    public static func resolveByID<T: Identifiable>(
        _ items: [T],
        identifiers: [T.ID]
    ) -> [T] where T.ID: Hashable {
        let wanted = Set(identifiers)
        return items.filter { wanted.contains($0.id) }
    }

    public static func matchString<T>(
        _ items: [T],
        query: String,
        title: (T) -> String,
        recency: (T) -> Date
    ) -> [T] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return items.sorted { recency($0) > recency($1) }
        }
        let needle = trimmed.lowercased()
        let matches = items.filter { title($0).lowercased().contains(needle) }
        if !matches.isEmpty {
            return matches.sorted { recency($0) > recency($1) }
        }
        return items
            .sorted { recency($0) > recency($1) }
            .filter { fuzzyContains(title($0).lowercased(), needle: needle) }
    }

    private static func fuzzyContains(_ haystack: String, needle: String) -> Bool {
        guard !needle.isEmpty else { return true }
        var h = haystack.startIndex
        for ch in needle {
            guard let idx = haystack[h...].firstIndex(of: ch) else { return false }
            h = haystack.index(after: idx)
        }
        return true
    }
}

// MARK: - Catalog

/// Loads stable entity snapshots from GRDB for Siri/App Intents resolution.
/// Relay machines and active run IDs are injected by the app target because
/// they live outside PersistenceKit.
public actor IntentEntityCatalog {
    private let db: AppDatabase

    public init(_ db: AppDatabase) {
        self.db = db
    }

    public func machines(relayMachines: [IntentRelayMachineSnapshot] = []) async throws -> [IntentMachineRecord] {
        let hosts = try await HostRepository(db).all()
        var records: [IntentMachineRecord] = hosts.map {
            IntentMachineRecord(
                id: "host:\($0.id.uuidString)",
                displayName: $0.name,
                hostName: $0.hostname,
                kind: .sshHost,
                lastConnectedAt: $0.lastConnectedAt
            )
        }
        for relay in relayMachines {
            records.append(
                IntentMachineRecord(
                    id: "relay:\(relay.id)",
                    displayName: relay.displayName,
                    hostName: relay.displayName,
                    kind: .relayMachine,
                    lastConnectedAt: relay.lastConnectedAt
                )
            )
        }
        return records.sorted {
            ($0.lastConnectedAt ?? .distantPast) > ($1.lastConnectedAt ?? .distantPast)
        }
    }

    public func machine(id: String, relayMachines: [IntentRelayMachineSnapshot] = []) async throws -> IntentMachineRecord? {
        try await machines(relayMachines: relayMachines).first { $0.id == id }
    }

    public func activeRuns(activeRunIDs: [String]) async throws -> [IntentRunRecord] {
        let chatRepo = ChatConversationRepository(db)
        var records: [IntentRunRecord] = []
        for runID in activeRunIDs {
            if let turn = try await chatRepo.turnByRunID(runID),
               let conv = try await chatRepo.conversation(id: turn.conversationID) {
                records.append(
                    IntentRunRecord(
                        id: runID,
                        title: conv.title,
                        conversationTitle: conv.title,
                        hostName: conv.hostName,
                        workspacePath: conv.cwd,
                        status: turn.status.rawValue
                    )
                )
            } else {
                records.append(IntentRunRecord(id: runID, title: "Agent run \(runID.prefix(8))"))
            }
        }
        return records.sorted { ($0.conversationTitle ?? $0.title) < ($1.conversationTitle ?? $1.title) }
    }

    public func run(id: String, activeRunIDs: [String]) async throws -> IntentRunRecord? {
        try await activeRuns(activeRunIDs: activeRunIDs).first { $0.id == id }
    }

    public func pendingApprovals() async throws -> [IntentApprovalRecord] {
        let approvals = try await ApprovalRepository(db).pending()
        return approvals.map(Self.approvalRecord)
    }

    public func approval(id: String) async throws -> IntentApprovalRecord? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        guard let dbApproval = try await ApprovalRepository(db).find(id: ApprovalID(uuid)) else {
            return nil
        }
        return Self.approvalRecord(dbApproval)
    }

    public func conversations(limit: Int = 50) async throws -> [IntentConversationRecord] {
        try await ChatConversationRepository(db).recent(limit: limit).map(Self.conversationRecord)
    }

    public func searchConversations(_ query: String, limit: Int = 50) async throws -> [IntentConversationRecord] {
        try await ChatConversationRepository(db).search(query, limit: limit).map {
            IntentConversationRecord(
                id: $0.conversation.id,
                title: $0.conversation.title,
                hostName: $0.conversation.hostName,
                workspacePath: $0.conversation.cwd,
                vendor: $0.conversation.vendor,
                lastActivityAt: $0.conversation.lastActivityAt,
                searchSnippet: $0.snippet
            )
        }
    }

    public func conversation(id: String) async throws -> IntentConversationRecord? {
        guard let conv = try await ChatConversationRepository(db).conversation(id: id) else { return nil }
        return Self.conversationRecord(conv)
    }

    public func workspaces(machineID: String? = nil) async throws -> [IntentWorkspaceRecord] {
        let repo = WorkspaceRepository(db)
        if let machineID, let relayID = UUID(uuidString: machineID) {
            return try await repo.list(machineID: RelayMachineID(relayID)).map(Self.workspaceRecord)
        }
        // No machine filter — return recent across all machines (bounded).
        return try await db.dbWriter.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM workspaces ORDER BY last_used_at DESC LIMIT 50
            """)
            return rows.compactMap { row -> IntentWorkspaceRecord? in
                guard let id: String = row["id"],
                      let name: String = row["name"],
                      let machineID: String = row["machine_id"],
                      let path: String = row["path"],
                      let lastUsed: Date = row["last_used_at"]
                else { return nil }
                return IntentWorkspaceRecord(id: id, name: name, machineID: machineID, path: path, lastUsedAt: lastUsed)
            }
        }
    }

    // MARK: - Private mappers

    private static func approvalRecord(_ approval: Approval) -> IntentApprovalRecord {
        let summary = ApprovalSummary.derive(from: approval)
        return IntentApprovalRecord(
            id: approval.id.uuidString,
            headline: summary.headline,
            riskLabel: riskLabel(approval.risk),
            hostName: nil,
            workspacePath: approval.cwd,
            agentLabel: approval.agent.rawValue,
            createdAt: approval.createdAt
        )
    }

    private static func conversationRecord(_ conv: ChatConversation) -> IntentConversationRecord {
        IntentConversationRecord(
            id: conv.id,
            title: conv.title,
            hostName: conv.hostName,
            workspacePath: conv.cwd,
            vendor: conv.vendor,
            lastActivityAt: conv.lastActivityAt
        )
    }

    private static func workspaceRecord(_ workspace: Workspace) -> IntentWorkspaceRecord {
        IntentWorkspaceRecord(
            id: workspace.id,
            name: workspace.name,
            machineID: workspace.machineID.uuidString,
            path: workspace.path,
            lastUsedAt: workspace.lastUsedAt
        )
    }

    private static func riskLabel(_ risk: Approval.Risk) -> String {
        switch risk {
        case .low: "low risk"
        case .medium: "medium risk"
        case .high: "high risk"
        case .critical: "critical risk"
        }
    }
}
