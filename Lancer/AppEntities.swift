import AppIntents
import Foundation
import PersistenceKit

// MARK: - Machine

@available(iOS 17.0, *)
struct MachineEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Machine")
    static var defaultQuery = MachineEntityQuery()

    let id: String
    let displayName: String
    let hostName: String
    let connectivityLabel: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(displayName)", subtitle: "\(connectivityLabel)")
    }

    init(_ record: IntentMachineRecord) {
        id = record.id
        displayName = record.displayName
        hostName = record.hostName
        connectivityLabel = SiriIntentSupport.machineConnectivityLabel(record)
    }
}

@available(iOS 17.0, *)
struct MachineEntityQuery: EntityQuery, EntityStringQuery {
    func entities(for identifiers: [MachineEntity.ID]) async throws -> [MachineEntity] {
        let catalog = try SiriIntentSupport.openCatalog()
        let relay = await SiriIntentSupport.relayMachineSnapshots()
        let all = try await catalog.machines(relayMachines: relay)
        return IntentEntityMatcher.resolveByID(all, identifiers: identifiers).map(MachineEntity.init)
    }

    func suggestedEntities() async throws -> [MachineEntity] {
        let catalog = try SiriIntentSupport.openCatalog()
        let relay = await SiriIntentSupport.relayMachineSnapshots()
        return try await catalog.machines(relayMachines: relay).prefix(6).map(MachineEntity.init)
    }

    func entities(matching string: String) async throws -> [MachineEntity] {
        let catalog = try SiriIntentSupport.openCatalog()
        let relay = await SiriIntentSupport.relayMachineSnapshots()
        let all = try await catalog.machines(relayMachines: relay)
        return IntentEntityMatcher.matchString(
            all,
            query: string,
            title: { $0.displayName + " " + $0.hostName },
            recency: { $0.lastConnectedAt ?? .distantPast }
        ).map(MachineEntity.init)
    }
}

// MARK: - Run

@available(iOS 17.0, *)
struct RunEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Agent Run")
    static var defaultQuery = RunEntityQuery()

    let id: String
    let title: String
    let subtitle: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(subtitle)")
    }

    init(_ record: IntentRunRecord) {
        id = record.id
        title = record.conversationTitle ?? record.title
        if let host = record.hostName {
            subtitle = host
        } else {
            subtitle = record.status
        }
    }
}

@available(iOS 17.0, *)
struct RunEntityQuery: EntityQuery, EntityStringQuery {
    @MainActor
    func entities(for identifiers: [RunEntity.ID]) async throws -> [RunEntity] {
        let catalog = try SiriIntentSupport.openCatalog()
        let active = SiriIntentSupport.activeRunIDs()
        let all = try await catalog.activeRuns(activeRunIDs: active)
        return IntentEntityMatcher.resolveByID(all, identifiers: identifiers).map(RunEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [RunEntity] {
        let catalog = try SiriIntentSupport.openCatalog()
        let active = SiriIntentSupport.activeRunIDs()
        return try await catalog.activeRuns(activeRunIDs: active).map(RunEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [RunEntity] {
        let catalog = try SiriIntentSupport.openCatalog()
        let active = SiriIntentSupport.activeRunIDs()
        let all = try await catalog.activeRuns(activeRunIDs: active)
        return IntentEntityMatcher.matchString(
            all,
            query: string,
            title: { ($0.conversationTitle ?? $0.title) + " " + ($0.hostName ?? "") },
            recency: { .now }
        ).map(RunEntity.init)
    }
}

// MARK: - Approval

@available(iOS 17.0, *)
struct ApprovalEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Approval")
    static var defaultQuery = ApprovalEntityQuery()

    let id: String
    let headline: String
    let riskLabel: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(headline)", subtitle: "\(riskLabel)")
    }

    init(_ record: IntentApprovalRecord) {
        id = record.id
        headline = record.headline
        riskLabel = record.riskLabel
    }
}

@available(iOS 17.0, *)
struct ApprovalEntityQuery: EntityQuery, EntityStringQuery {
    func entities(for identifiers: [ApprovalEntity.ID]) async throws -> [ApprovalEntity] {
        let catalog = try SiriIntentSupport.openCatalog()
        let all = try await catalog.pendingApprovals()
        return IntentEntityMatcher.resolveByID(all, identifiers: identifiers).map(ApprovalEntity.init)
    }

    func suggestedEntities() async throws -> [ApprovalEntity] {
        let catalog = try SiriIntentSupport.openCatalog()
        return try await catalog.pendingApprovals().map(ApprovalEntity.init)
    }

    func entities(matching string: String) async throws -> [ApprovalEntity] {
        let catalog = try SiriIntentSupport.openCatalog()
        let all = try await catalog.pendingApprovals()
        return IntentEntityMatcher.matchString(
            all,
            query: string,
            title: { $0.headline + " " + $0.workspacePath + " " + $0.agentLabel },
            recency: { $0.createdAt }
        ).map(ApprovalEntity.init)
    }
}

// MARK: - Conversation

@available(iOS 17.0, *)
struct ConversationEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Conversation")
    static var defaultQuery = ConversationEntityQuery()

    let id: String
    let title: String
    let hostName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(hostName)")
    }

    init(_ record: IntentConversationRecord) {
        id = record.id
        title = record.title
        hostName = record.hostName
    }
}

@available(iOS 17.0, *)
struct ConversationEntityQuery: EntityQuery, EntityStringQuery {
    func entities(for identifiers: [ConversationEntity.ID]) async throws -> [ConversationEntity] {
        let catalog = try SiriIntentSupport.openCatalog()
        var resolved: [IntentConversationRecord] = []
        for id in identifiers {
            if let conv = try await catalog.conversation(id: id) {
                resolved.append(conv)
            }
        }
        return resolved.map(ConversationEntity.init)
    }

    func suggestedEntities() async throws -> [ConversationEntity] {
        let catalog = try SiriIntentSupport.openCatalog()
        return try await catalog.conversations(limit: 8).map(ConversationEntity.init)
    }

    func entities(matching string: String) async throws -> [ConversationEntity] {
        let catalog = try SiriIntentSupport.openCatalog()
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let records: [IntentConversationRecord]
        if trimmed.isEmpty {
            records = try await catalog.conversations()
        } else {
            records = try await catalog.searchConversations(trimmed)
        }
        return records.map(ConversationEntity.init)
    }
}

// MARK: - Workspace

@available(iOS 17.0, *)
struct WorkspaceEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Workspace")
    static var defaultQuery = WorkspaceEntityQuery()

    let id: String
    let name: String
    let path: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(path)")
    }

    init(_ record: IntentWorkspaceRecord) {
        id = record.id
        name = record.name
        path = record.path
    }
}

@available(iOS 17.0, *)
struct WorkspaceEntityQuery: EntityQuery, EntityStringQuery {
    func entities(for identifiers: [WorkspaceEntity.ID]) async throws -> [WorkspaceEntity] {
        let catalog = try SiriIntentSupport.openCatalog()
        let all = try await catalog.workspaces()
        return IntentEntityMatcher.resolveByID(all, identifiers: identifiers).map(WorkspaceEntity.init)
    }

    func suggestedEntities() async throws -> [WorkspaceEntity] {
        let catalog = try SiriIntentSupport.openCatalog()
        return try await catalog.workspaces().prefix(8).map(WorkspaceEntity.init)
    }

    func entities(matching string: String) async throws -> [WorkspaceEntity] {
        let catalog = try SiriIntentSupport.openCatalog()
        let all = try await catalog.workspaces()
        return IntentEntityMatcher.matchString(
            all,
            query: string,
            title: { $0.name + " " + $0.path },
            recency: { $0.lastUsedAt }
        ).map(WorkspaceEntity.init)
    }
}
