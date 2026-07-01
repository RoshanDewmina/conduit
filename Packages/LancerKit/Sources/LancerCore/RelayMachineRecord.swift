import Foundation

/// One paired relay machine. Lane 0 of multi-machine relay support: this is
/// the record type later lanes persist/list/select against — this file does
/// not itself wire into any live store.
public struct RelayMachineRecord: Identifiable, Sendable, Codable, Hashable {
    public let id: RelayMachineID
    public var displayName: String
    public let pairedAt: Date
    public var lastConnectedAt: Date?

    public init(
        id: RelayMachineID = .init(),
        displayName: String,
        pairedAt: Date = .now,
        lastConnectedAt: Date? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.pairedAt = pairedAt
        self.lastConnectedAt = lastConnectedAt
    }
}

/// Cap policy for the paired-machine fleet: at most `relayFleetMaxMachines`
/// machines may be paired at once.
public let relayFleetMaxMachines = 3

public func isRelayFleetFull(count: Int) -> Bool {
    count >= relayFleetMaxMachines
}
