#if canImport(AppIntents)
import AppIntents
import Foundation
import LancerCore
import PersistenceKit
import SSHTransport

@available(iOS 17.0, *)
public struct MachineEntity: AppEntity, Identifiable, Sendable {
  public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Machine")
  public static let defaultQuery = MachineEntityQuery()

  /// Which pairing transport this machine was surfaced from — Siri Phase 2's
  /// `StartAgentRunIntent` only dispatches to `.relay` (the app's fire-and-
  /// forget WebSocket bridge, reachable cold); `.sshHost` machines need an
  /// already-open in-app session, which App Intents can't establish, so
  /// `StartAgentRunPreparer` rejects them with a clear dialog instead of
  /// silently failing "Host is no longer connected."
  public enum Kind: Sendable, Equatable {
    case sshHost
    case relayMachine
  }

  public let id: String
  public let name: String
  public let hostname: String
  public let kind: Kind
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
    kind = .sshHost
    lastConnectedAt = host.lastConnectedAt
  }

  /// Relay-paired machines have no separate "hostname" (the phone never
  /// resolves a hostname/IP for them — the relay does that routing) so the
  /// entity's `hostname` mirrors `name`, matching how `AgentStatusQueryIntent`
  /// already formats "\(name) (\(hostname))".
  init(relay record: RelayMachineRecord) {
    id = "relay:\(record.id.uuidString)"
    name = record.displayName
    hostname = record.displayName
    kind = .relayMachine
    lastConnectedAt = record.lastConnectedAt
  }

  /// Strips the `"relay:"` id prefix and parses the underlying `RelayMachineID`,
  /// or `nil` for an `.sshHost` entity (whose id is a bare Host UUID).
  public var relayMachineID: RelayMachineID? {
    guard kind == .relayMachine, id.hasPrefix("relay:") else { return nil }
    guard let uuid = UUID(uuidString: String(id.dropFirst("relay:".count))) else { return nil }
    return RelayMachineID(uuid)
  }
}

@available(iOS 17.0, *)
public struct MachineEntityQuery: EntityQuery, EntityStringQuery {
  public init() {}

  private func allMachines() async throws -> [MachineEntity] {
    let db = try IntentsKitDependencies.database()
    let hosts = try await HostRepository(db).all()
    let relayMachines = await IntentsKitDependencies.relayMachineSnapshots()
    return hosts.map(MachineEntity.init) + relayMachines.map(MachineEntity.init)
  }

  public func entities(for identifiers: [MachineEntity.ID]) async throws -> [MachineEntity] {
    let all = try await allMachines()
    let wanted = Set(identifiers)
    return all.filter { wanted.contains($0.id) }
  }

  public func suggestedEntities() async throws -> [MachineEntity] {
    try await allMachines()
  }

  public func entities(matching string: String) async throws -> [MachineEntity] {
    let all = try await allMachines()
    let query = IntentsKitSupport.normalizedQuery(string)
    guard !query.isEmpty else { return all }
    return all.filter {
      IntentsKitSupport.matchesFuzzy($0.name, query: query)
        || IntentsKitSupport.matchesFuzzy($0.hostname, query: query)
    }
  }
}

#endif
