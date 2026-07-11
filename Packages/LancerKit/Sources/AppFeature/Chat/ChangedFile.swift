import Foundation

/// One file row in a Changes card / PR file list (presentation model).
public struct ChangedFile: Identifiable, Equatable, Sendable {
    public let id: String
    public let badge: String
    public let name: String
    public let added: Int
    public let removed: Int

    public init(id: String = UUID().uuidString, badge: String, name: String, added: Int, removed: Int) {
        self.id = id
        self.badge = badge
        self.name = name
        self.added = added
        self.removed = removed
    }

    public var diff: DiffCountFormat { DiffCountFormat(added: added, removed: removed) }
}
