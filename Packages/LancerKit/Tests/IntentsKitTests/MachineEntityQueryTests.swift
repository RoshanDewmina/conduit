#if canImport(AppIntents)
import Foundation
import Testing
import LancerCore
import PersistenceKit
@testable import IntentsKit

@Suite("MachineEntityQuery")
struct MachineEntityQueryTests {
  @Test("exact ID resolves the machine")
  func exactIDHit() async throws {
    try await IntentsKitTestFixtures.withDatabase { db in
      let lastConnected = Date(timeIntervalSince1970: 1_700_000_000)
      let host = LancerCore.Host(
        name: "mac-studio", hostname: "studio.local", username: "dev",
        lastConnectedAt: lastConnected
      )
      try await HostRepository(db).upsert(host)

      let query = MachineEntityQuery()
      let hits = try await query.entities(for: [host.id.uuidString])
      #expect(hits.count == 1)
      #expect(hits[0].name == "mac-studio")
      #expect(hits[0].lastConnectedAt == lastConnected)
    }
  }

  @Test("fuzzy title matches host name")
  func fuzzyTitleHit() async throws {
    try await IntentsKitTestFixtures.withDatabase { db in
      try await HostRepository(db).upsert(
        LancerCore.Host(name: "mac-studio", hostname: "studio.local", username: "dev")
      )

      let hits = try await MachineEntityQuery().entities(matching: "studio")
      #expect(hits.count == 1)
      #expect(hits[0].name == "mac-studio")
    }
  }

  @Test("ambiguous query returns multiple machines")
  func ambiguousMultiple() async throws {
    try await IntentsKitTestFixtures.withDatabase { db in
      let repo = HostRepository(db)
      try await repo.upsert(LancerCore.Host(name: "dev-mac", hostname: "dev.local", username: "dev"))
      try await repo.upsert(LancerCore.Host(name: "prod-mac", hostname: "prod.local", username: "dev"))

      let hits = try await MachineEntityQuery().entities(matching: "mac")
      #expect(hits.count == 2)
    }
  }

  @Test("relay machines merge with SSH hosts")
  func relayMerge() async throws {
    let record = RelayMachineRecord(displayName: "Relay Mac", lastConnectedAt: .now)
    try await IntentsKitTestFixtures.withDatabase(relayMachines: [record]) { db in
      try await HostRepository(db).upsert(
        LancerCore.Host(name: "Studio Mac", hostname: "studio.local", username: "dev")
      )

      let all = try await MachineEntityQuery().suggestedEntities()
      #expect(all.count == 2)
      let relay = try #require(all.first { $0.kind == .relayMachine })
      #expect(relay.id == "relay:\(record.id.uuidString)")
      #expect(relay.name == "Relay Mac")
      #expect(relay.hostname == "Relay Mac")
      #expect(all.first { $0.kind == .sshHost }?.name == "Studio Mac")
    }
  }

  @Test("relay-prefixed ID resolves and round-trips relayMachineID")
  func relayIDResolution() async throws {
    let lastConnected = Date(timeIntervalSince1970: 1_700_000_000)
    let record = RelayMachineRecord(displayName: "Relay Mac", lastConnectedAt: lastConnected)
    try await IntentsKitTestFixtures.withDatabase(relayMachines: [record]) { _ in
      let hits = try await MachineEntityQuery().entities(for: ["relay:\(record.id.uuidString)"])
      #expect(hits.count == 1)
      #expect(hits[0].kind == .relayMachine)
      #expect(hits[0].relayMachineID == record.id)
      #expect(hits[0].lastConnectedAt == lastConnected)
    }
  }

  @Test("sshHost entity has nil relayMachineID")
  func sshHostHasNoRelayID() async throws {
    try await IntentsKitTestFixtures.withDatabase { db in
      let host = LancerCore.Host(name: "mac-studio", hostname: "studio.local", username: "dev")
      try await HostRepository(db).upsert(host)

      let hits = try await MachineEntityQuery().entities(for: [host.id.uuidString])
      #expect(hits.count == 1)
      #expect(hits[0].kind == .sshHost)
      #expect(hits[0].relayMachineID == nil)
    }
  }

  @Test("fuzzy match hits relay display name")
  func fuzzyRelayHit() async throws {
    let record = RelayMachineRecord(displayName: "hermes-box")
    try await IntentsKitTestFixtures.withDatabase(relayMachines: [record]) { db in
      try await HostRepository(db).upsert(
        LancerCore.Host(name: "mac-studio", hostname: "studio.local", username: "dev")
      )

      let hits = try await MachineEntityQuery().entities(matching: "hermes")
      #expect(hits.count == 1)
      #expect(hits[0].kind == .relayMachine)
      #expect(hits[0].name == "hermes-box")
    }
  }

  @Test("ambiguous query spans SSH hosts and relay machines")
  func ambiguousAcrossKinds() async throws {
    let record = RelayMachineRecord(displayName: "relay-mac")
    try await IntentsKitTestFixtures.withDatabase(relayMachines: [record]) { db in
      try await HostRepository(db).upsert(
        LancerCore.Host(name: "dev-mac", hostname: "dev.local", username: "dev")
      )

      let hits = try await MachineEntityQuery().entities(matching: "mac")
      #expect(hits.count == 2)
      #expect(Set(hits.map(\.kind)) == [.sshHost, .relayMachine])
    }
  }

  @Test("empty store returns no machines")
  func emptyStore() async throws {
    try await IntentsKitTestFixtures.withDatabase { _ in
      let query = MachineEntityQuery()
      let suggested = try await query.suggestedEntities()
      let byID = try await query.entities(for: ["missing"])
      let byTitle = try await query.entities(matching: "anything")
      #expect(suggested.isEmpty)
      #expect(byID.isEmpty)
      #expect(byTitle.isEmpty)
    }
  }
}
#endif
