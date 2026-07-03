import Foundation

/// A persisted, named project directory scoped to a machine — the
/// Machine → Workspace → Chat middle layer. Replaces the flat, unscoped
/// `@AppStorage` MRU path cache the New Chat composer used to rely on with a
/// real, creatable, renameable record (see `WorkspaceRepository`).
public struct Workspace: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public var name: String
    public var machineID: RelayMachineID
    public var path: String
    public var lastBranch: String?
    public let createdAt: Date
    public var lastUsedAt: Date

    public init(
        id: String = UUID().uuidString,
        name: String,
        machineID: RelayMachineID,
        path: String,
        lastBranch: String? = nil,
        createdAt: Date = .now,
        lastUsedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.machineID = machineID
        self.path = path
        self.lastBranch = lastBranch
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }
}
