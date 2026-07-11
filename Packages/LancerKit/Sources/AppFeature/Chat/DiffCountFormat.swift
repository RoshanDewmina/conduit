import Foundation

/// Pure presentation formatting for green/red +/− diff counts (Cursor thread Changes rows / View PR pills).
public struct DiffCountFormat: Equatable, Sendable {
    public let added: Int
    public let removed: Int

    public init(added: Int, removed: Int) {
        self.added = max(0, added)
        self.removed = max(0, removed)
    }

    public var addedLabel: String { "+\(added)" }
    public var removedLabel: String { "-\(removed)" }

    /// Space-separated pair matching Cursor pills, e.g. `+858 -38`.
    public var combinedLabel: String { "\(addedLabel) \(removedLabel)" }
}
