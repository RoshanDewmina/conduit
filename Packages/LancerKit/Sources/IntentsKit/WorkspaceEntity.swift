#if canImport(AppIntents)
import AppIntents
import Foundation
import LancerCore
import PersistenceKit

/// A named project directory on a relay-paired machine (`WorkspaceRepository`,
/// scoped by `RelayMachineID`) — the "which folder should the agent work in"
/// parameter for `StartAgentRunIntent` (Siri Phase 2).
@available(iOS 17.0, *)
public struct WorkspaceEntity: AppEntity, Identifiable, Sendable {
  public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Workspace")
  public static let defaultQuery = WorkspaceEntityQuery()

  public let id: String
  public let name: String
  public let path: String
  public let machineID: RelayMachineID

  public var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(name)", subtitle: "\(path)")
  }

  init(_ workspace: Workspace) {
    id = workspace.id
    name = workspace.name
    path = workspace.path
    machineID = workspace.machineID
  }
}

@available(iOS 17.0, *)
public struct WorkspaceEntityQuery: EntityQuery, EntityStringQuery {
  public init() {}

  /// Workspaces are relay-machine-scoped (`WorkspaceRepository.list(machineID:)`
  /// takes one machine); the Siri parameter has no narrowed-to-a-machine
  /// context to hand in, so this flattens across every paired relay machine —
  /// the same "list everything, let fuzzy matching narrow it" shape
  /// `MachineEntityQuery`/`ConversationEntityQuery` already use.
  private func allWorkspaces() async throws -> [WorkspaceEntity] {
    let db = try IntentsKitDependencies.database()
    let repo = WorkspaceRepository(db)
    let relayMachines = await IntentsKitDependencies.relayMachineSnapshots()
    var all: [Workspace] = []
    for machine in relayMachines {
      all.append(contentsOf: try await repo.list(machineID: machine.id))
    }
    return all.sorted { $0.lastUsedAt > $1.lastUsedAt }.map(WorkspaceEntity.init)
  }

  public func entities(for identifiers: [WorkspaceEntity.ID]) async throws -> [WorkspaceEntity] {
    let all = try await allWorkspaces()
    let wanted = Set(identifiers)
    return all.filter { wanted.contains($0.id) }
  }

  public func suggestedEntities() async throws -> [WorkspaceEntity] {
    Array(try await allWorkspaces().prefix(8))
  }

  public func entities(matching string: String) async throws -> [WorkspaceEntity] {
    let all = try await allWorkspaces()
    let query = IntentsKitSupport.normalizedQuery(string)
    guard !query.isEmpty else { return all }
    return all.filter {
      IntentsKitSupport.matchesFuzzy($0.name, query: query)
        || IntentsKitSupport.matchesFuzzy($0.path, query: query)
    }
  }
}

#endif
