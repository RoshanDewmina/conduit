import Foundation

/// Compact post-turn activity stats for the secondary "Worked Ns · …" row.
public struct TurnActivitySummary: Equatable, Sendable {
    public let durationSeconds: Int
    public let editedFileCount: Int
    public let exploredCount: Int
    public let searchCount: Int
    public let added: Int?
    public let removed: Int?

    public init(
        durationSeconds: Int,
        editedFileCount: Int,
        exploredCount: Int,
        searchCount: Int,
        added: Int? = nil,
        removed: Int? = nil
    ) {
        self.durationSeconds = max(0, durationSeconds)
        self.editedFileCount = max(0, editedFileCount)
        self.exploredCount = max(0, exploredCount)
        self.searchCount = max(0, searchCount)
        self.added = added.map { max(0, $0) }
        self.removed = removed.map { max(0, $0) }
    }

    /// Cursor-style single line, e.g. `Worked 59s · Edited 2 files · 3 searches · +38 −38`.
    public var label: String {
        var parts: [String] = ["Worked \(Self.formatDuration(durationSeconds))"]
        if editedFileCount > 0 {
            parts.append(editedFileCount == 1 ? "Edited 1 file" : "Edited \(editedFileCount) files")
        }
        if exploredCount > 0 {
            parts.append(exploredCount == 1 ? "Explored 1" : "Explored \(exploredCount)")
        }
        if searchCount > 0 {
            parts.append(searchCount == 1 ? "1 search" : "\(searchCount) searches")
        }
        if let added, let removed {
            parts.append("+\(added) −\(removed)")
        } else if let added {
            parts.append("+\(added)")
        } else if let removed {
            parts.append("−\(removed)")
        }
        return parts.joined(separator: " · ")
    }

    public static func formatDuration(_ totalSeconds: Int) -> String {
        LiveStatusPresentation.formatElapsed(totalSeconds)
    }
}
