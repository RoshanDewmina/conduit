#if canImport(AppIntents)
import AppIntents
import Foundation
import LancerCore
import PersistenceKit

@available(iOS 17.0, *)
public struct MachineEntity: AppEntity, Identifiable, Sendable {
  public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Machine")
  public static let defaultQuery = MachineEntityQuery()

  public let id: String
  public let name: String
  public let hostname: String
  /// Freshness signal for Siri answers (D3): a status dialog naming this machine
  /// must say how stale the phone's knowledge of it is, not answer confidently
  /// from an old row.
  public let lastConnectedAt: Date?

  public var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(name)")
  }

  init(host: LancerCore.Host) {
    id = host.id.uuidString
    name = host.name
    hostname = host.hostname
    lastConnectedAt = host.lastConnectedAt
  }
}

@available(iOS 17.0, *)
public struct MachineEntityQuery: EntityQuery, EntityStringQuery {
  public init() {}

  public func entities(for identifiers: [MachineEntity.ID]) async throws -> [MachineEntity] {
    let db = try IntentsKitDependencies.database()
    let hosts = try await HostRepository(db).all()
    let wanted = Set(identifiers)
    return hosts
      .filter { wanted.contains($0.id.uuidString) }
      .map(MachineEntity.init)
  }

  public func suggestedEntities() async throws -> [MachineEntity] {
    let db = try IntentsKitDependencies.database()
    let hosts = try await HostRepository(db).all()
    return hosts.map(MachineEntity.init)
  }

  public func entities(matching string: String) async throws -> [MachineEntity] {
    let db = try IntentsKitDependencies.database()
    let hosts = try await HostRepository(db).all()
    let query = IntentsKitSupport.normalizedQuery(string)
    guard !query.isEmpty else { return hosts.map(MachineEntity.init) }
    return hosts.filter {
      IntentsKitSupport.matchesFuzzy($0.name, query: query)
        || IntentsKitSupport.matchesFuzzy($0.hostname, query: query)
    }
    .map(MachineEntity.init)
  }
}

#endif
