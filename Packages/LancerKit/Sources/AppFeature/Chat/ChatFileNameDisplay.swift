import Foundation

/// Filename truncation for Changes rows (middle ellipsis, Cursor-style).
public enum ChatFileNameDisplay: Sendable {
    public static func truncated(_ name: String, maxLength: Int = 28) -> String {
        guard maxLength > 3, name.count > maxLength else { return name }
        let keep = maxLength - 1 // room for …
        let head = keep / 2
        let tail = keep - head
        let start = name.prefix(head)
        let end = name.suffix(tail)
        return "\(start)…\(end)"
    }

    /// Basename for display when a path is provided.
    public static func displayName(for pathOrName: String) -> String {
        if let slash = pathOrName.lastIndex(of: "/") {
            return String(pathOrName[pathOrName.index(after: slash)...])
        }
        return pathOrName
    }
}
