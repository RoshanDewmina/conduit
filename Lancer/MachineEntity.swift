import AppIntents
import Foundation
import LancerCore
import SSHTransport

// Lives in the `Lancer` app target — see StatusQueryIntents.swift's header
// comment for why (dual-target AppIntent compilation breaks runtime execution
// lookup even though static Shortcuts discovery still works).

/// Wraps a paired relay machine (`RelayMachineRecord`). `IndexedEntity`, not
/// volatile: a paired-machine fleet is small (≤3, `relayFleetMaxMachines`) and
/// low-churn — machines are added/renamed/removed by explicit user action, not
/// created and torn down every few seconds like a run or an approval — so
/// indexing genuinely pays for itself here, per the audit's durable/volatile
/// split. No existing Siri intent needs machine disambiguation yet; this is
/// forward groundwork, not a fix for a live bug.
@available(iOS 18.0, *)
public struct MachineEntity: IndexedEntity {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Machine")
    public static let defaultQuery = MachineEntityQuery()

    public let id: String
    let displayName: String
    let lastConnectedAt: Date?

    public var displayRepresentation: DisplayRepresentation {
        if let lastConnectedAt {
            return DisplayRepresentation(
                title: "\(displayName)",
                subtitle: "Last connected \(lastConnectedAt.formatted(date: .abbreviated, time: .shortened))"
            )
        }
        return DisplayRepresentation(title: "\(displayName)")
    }

    init(record: RelayMachineRecord) {
        self.id = record.id.uuidString
        self.displayName = record.displayName
        self.lastConnectedAt = record.lastConnectedAt
    }
}

@available(iOS 18.0, *)
public struct MachineEntityQuery: EntityStringQuery {
    public init() {}

    @MainActor
    private func allRecords() async -> [RelayMachineRecord] {
        await RelayMachineMigration.readIndex()
    }

    public func entities(for identifiers: [String]) async throws -> [MachineEntity] {
        let records = await allRecords()
        return identifiers.compactMap { id in
            records.first(where: { $0.id.uuidString == id }).map(MachineEntity.init)
        }
    }

    public func entities(matching string: String) async throws -> [MachineEntity] {
        let records = await allRecords()
        return records
            .filter { $0.displayName.localizedCaseInsensitiveContains(string) }
            .map(MachineEntity.init)
    }

    public func suggestedEntities() async throws -> [MachineEntity] {
        await allRecords().map(MachineEntity.init)
    }
}
