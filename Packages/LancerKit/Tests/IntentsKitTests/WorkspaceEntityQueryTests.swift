#if canImport(AppIntents)
import Foundation
import Testing
import LancerCore
import PersistenceKit
@testable import IntentsKit

@Suite("WorkspaceEntityQuery")
struct WorkspaceEntityQueryTests {
  @Test("exact ID resolves the workspace")
  func exactIDHit() async throws {
    let machine = RelayMachineRecord(displayName: "Relay Mac")
    try await IntentsKitTestFixtures.withDatabase(relayMachines: [machine]) { db in
      let ws = try await WorkspaceRepository(db).create(
        name: "gateway", machineID: machine.id, path: "/Users/dev/repos/gateway"
      )

      let hits = try await WorkspaceEntityQuery().entities(for: [ws.id])
      #expect(hits.count == 1)
      #expect(hits[0].name == "gateway")
      #expect(hits[0].path == "/Users/dev/repos/gateway")
      #expect(hits[0].machineID == machine.id)
    }
  }

  @Test("fuzzy match hits name and path")
  func fuzzyNameAndPath() async throws {
    let machine = RelayMachineRecord(displayName: "Relay Mac")
    try await IntentsKitTestFixtures.withDatabase(relayMachines: [machine]) { db in
      let repo = WorkspaceRepository(db)
      try await repo.create(name: "gateway", machineID: machine.id, path: "/repos/gateway")
      try await repo.create(name: "billing", machineID: machine.id, path: "/repos/billing-ui")

      let byName = try await WorkspaceEntityQuery().entities(matching: "gateway")
      #expect(byName.count == 1)
      #expect(byName[0].name == "gateway")

      let byPath = try await WorkspaceEntityQuery().entities(matching: "billing-ui")
      #expect(byPath.count == 1)
      #expect(byPath[0].name == "billing")
    }
  }

  @Test("results sort most-recently-used first across machines")
  func mruOrdering() async throws {
    let machineA = RelayMachineRecord(displayName: "Mac A")
    let machineB = RelayMachineRecord(displayName: "Mac B")
    try await IntentsKitTestFixtures.withDatabase(relayMachines: [machineA, machineB]) { db in
      let repo = WorkspaceRepository(db)
      let older = try await repo.create(name: "older", machineID: machineA.id, path: "/a/older")
      let newer = try await repo.create(name: "newer", machineID: machineB.id, path: "/b/newer")
      try await repo.touch(newer.id)

      let all = try await WorkspaceEntityQuery().suggestedEntities()
      #expect(all.map(\.id) == [newer.id, older.id])
    }
  }

  @Test("suggestions cap at 8")
  func suggestionCap() async throws {
    let machine = RelayMachineRecord(displayName: "Relay Mac")
    try await IntentsKitTestFixtures.withDatabase(relayMachines: [machine]) { db in
      let repo = WorkspaceRepository(db)
      for i in 0..<10 {
        try await repo.create(name: "ws-\(i)", machineID: machine.id, path: "/repos/ws-\(i)")
      }

      let suggested = try await WorkspaceEntityQuery().suggestedEntities()
      #expect(suggested.count == 8)

      let all = try await WorkspaceEntityQuery().entities(matching: "")
      #expect(all.count == 10)
    }
  }

  @Test("workspaces on unpaired machines are invisible")
  func unpairedMachineExcluded() async throws {
    let paired = RelayMachineRecord(displayName: "Paired Mac")
    let unpaired = RelayMachineID()
    try await IntentsKitTestFixtures.withDatabase(relayMachines: [paired]) { db in
      let repo = WorkspaceRepository(db)
      try await repo.create(name: "visible", machineID: paired.id, path: "/p/visible")
      let orphan = try await repo.create(name: "orphan", machineID: unpaired, path: "/u/orphan")

      let query = WorkspaceEntityQuery()
      let suggested = try await query.suggestedEntities()
      #expect(suggested.map(\.name) == ["visible"])
      let byID = try await query.entities(for: [orphan.id])
      #expect(byID.isEmpty)
    }
  }

  @Test("empty store returns no workspaces")
  func emptyStore() async throws {
    try await IntentsKitTestFixtures.withDatabase { _ in
      let query = WorkspaceEntityQuery()
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
