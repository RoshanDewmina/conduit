// iOS 26 launch lane — AppEntity types for Siri/Shortcuts disambiguation.
// iOS 27-only APIs (AppIntentsTesting, IndexedEntityQuery, IntentExecutionTargets)
// live in docs/wwdc26-lancer-opportunity-audit/ios27-fast-follow.md.

import AppIntents
import Foundation
import PersistenceKit

// MARK: - Machine

@available(iOS 17.0, *)
public struct MachineEntity: AppEntity, Identifiable {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Machine")
    public static let defaultQuery = MachineEntityQuery()

    public let id: String
    public let displayName: String
    public let hostName: String
    public let connectivityLabel: String

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(displayName)", subtitle: "\(connectivityLabel)")
    }

    public init(_ record: IntentMachineRecord) {
        id = record.id
        displayName = record.displayName
        hostName = record.hostName
        connectivityLabel = SiriIntentSupport.machineConnectivityLabel(record)
    }
}

@available(iOS 17.0, *)
public struct MachineEntityQuery: EntityQuery, EntityStringQuery {
    public init() {}

    public func entities(for identifiers: [MachineEntity.ID]) async throws -> [MachineEntity] {
        let catalog = try SiriIntentSupport.openCatalog()
        let relay = await SiriIntentSupport.relayMachineSnapshots()
        let all = try await catalog.machines(relayMachines: relay)
        return IntentEntityMatcher.resolveByID(all, identifiers: identifiers).map(MachineEntity.init)
    }

    public func suggestedEntities() async throws -> [MachineEntity] {
        let catalog = try SiriIntentSupport.openCatalog()
        let relay = await SiriIntentSupport.relayMachineSnapshots()
        return try await catalog.machines(relayMachines: relay).prefix(6).map(MachineEntity.init)
    }

    public func entities(matching string: String) async throws -> [MachineEntity] {
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
public struct RunEntity: AppEntity, Identifiable {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Agent Run")
    public static let defaultQuery = RunEntityQuery()

    public let id: String
    public let title: String
    public let subtitle: String

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(subtitle)")
    }

    public init(_ record: IntentRunRecord) {
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
public struct RunEntityQuery: EntityQuery, EntityStringQuery {
    public init() {}

    @MainActor
    public func entities(for identifiers: [RunEntity.ID]) async throws -> [RunEntity] {
        let catalog = try SiriIntentSupport.openCatalog()
        let active = SiriIntentSupport.activeRunIDs()
        let all = try await catalog.activeRuns(activeRunIDs: active)
        return IntentEntityMatcher.resolveByID(all, identifiers: identifiers).map(RunEntity.init)
    }

    @MainActor
    public func suggestedEntities() async throws -> [RunEntity] {
        let catalog = try SiriIntentSupport.openCatalog()
        let active = SiriIntentSupport.activeRunIDs()
        return try await catalog.activeRuns(activeRunIDs: active).map(RunEntity.init)
    }

    @MainActor
    public func entities(matching string: String) async throws -> [RunEntity] {
        let catalog = try SiriIntentSupport.openCatalog()
        let active = SiriIntentSupport.activeRunIDs()
        let all = try await catalog.activeRuns(activeRunIDs: active)
        return IntentEntityMatcher.matchString(
            all,
            query: string,
            title: { ($0.conversationTitle ?? $0.title) + " " + ($0.hostName ?? "") },
            recency: { _ in .now }
        ).map(RunEntity.init)
    }
}

// MARK: - Approval

@available(iOS 17.0, *)
public struct ApprovalEntity: AppEntity, Identifiable {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Approval")
    public static let defaultQuery = ApprovalEntityQuery()

    public let id: String
    public let headline: String
    public let riskLabel: String

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(headline)", subtitle: "\(riskLabel)")
    }

    public init(_ record: IntentApprovalRecord) {
        id = record.id
        headline = record.headline
        riskLabel = record.riskLabel
    }
}

@available(iOS 17.0, *)
public struct ApprovalEntityQuery: EntityQuery, EntityStringQuery {
    public init() {}

    public func entities(for identifiers: [ApprovalEntity.ID]) async throws -> [ApprovalEntity] {
        let catalog = try SiriIntentSupport.openCatalog()
        let all = try await catalog.pendingApprovals()
        return IntentEntityMatcher.resolveByID(all, identifiers: identifiers).map(ApprovalEntity.init)
    }

    public func suggestedEntities() async throws -> [ApprovalEntity] {
        let catalog = try SiriIntentSupport.openCatalog()
        return try await catalog.pendingApprovals().map(ApprovalEntity.init)
    }

    public func entities(matching string: String) async throws -> [ApprovalEntity] {
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
public struct ConversationEntity: AppEntity, Identifiable {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Conversation")
    public static let defaultQuery = ConversationEntityQuery()

    public let id: String
    public let title: String
    public let hostName: String

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(hostName)")
    }

    public init(_ record: IntentConversationRecord) {
        id = record.id
        title = record.title
        hostName = record.hostName
    }
}

@available(iOS 17.0, *)
public struct ConversationEntityQuery: EntityQuery, EntityStringQuery {
    public init() {}

    public func entities(for identifiers: [ConversationEntity.ID]) async throws -> [ConversationEntity] {
        let catalog = try SiriIntentSupport.openCatalog()
        var resolved: [IntentConversationRecord] = []
        for id in identifiers {
            if let conv = try await catalog.conversation(id: id) {
                resolved.append(conv)
            }
        }
        return resolved.map(ConversationEntity.init)
    }

    public func suggestedEntities() async throws -> [ConversationEntity] {
        let catalog = try SiriIntentSupport.openCatalog()
        return try await catalog.conversations(limit: 8).map(ConversationEntity.init)
    }

    public func entities(matching string: String) async throws -> [ConversationEntity] {
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
public struct WorkspaceEntity: AppEntity, Identifiable {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Workspace")
    public static let defaultQuery = WorkspaceEntityQuery()

    public let id: String
    public let name: String
    public let path: String

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(path)")
    }

    public init(_ record: IntentWorkspaceRecord) {
        id = record.id
        name = record.name
        path = record.path
    }
}

@available(iOS 17.0, *)
public struct WorkspaceEntityQuery: EntityQuery, EntityStringQuery {
    public init() {}

    public func entities(for identifiers: [WorkspaceEntity.ID]) async throws -> [WorkspaceEntity] {
        let catalog = try SiriIntentSupport.openCatalog()
        let all = try await catalog.workspaces()
        return IntentEntityMatcher.resolveByID(all, identifiers: identifiers).map(WorkspaceEntity.init)
    }

    public func suggestedEntities() async throws -> [WorkspaceEntity] {
        let catalog = try SiriIntentSupport.openCatalog()
        return try await catalog.workspaces().prefix(8).map(WorkspaceEntity.init)
    }

    public func entities(matching string: String) async throws -> [WorkspaceEntity] {
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
