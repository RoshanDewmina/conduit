#if os(iOS)
import SwiftUI

/// Font definitions for the Cursor-style look. Chrome uses SF Rounded; code and
/// diff content stay monospaced per the 2026-07-08 reference.
public enum CursorType {
    public static let pageTitle = rounded(size: 32, weight: .bold)
    public static let sheetTitle = rounded(size: 17, weight: .semibold)
    public static let rowTitle = rounded(size: 17, weight: .regular)
    public static let rowSecondary = rounded(size: 13, weight: .regular)
    public static let sectionHeader = rounded(size: 13, weight: .regular)
    public static let composerPlaceholder = rounded(size: 16, weight: .regular)

    /// Work Thread narration prose.
    public static let bodyText = rounded(size: 16, weight: .regular)
    /// Bold inline labels within narration (e.g. "Why:", "Worktree locations").
    public static let bodyEmphasis = rounded(size: 16, weight: .semibold)
    /// Inline code-styled file-path chips.
    public static let inlineCode = mono(size: 15, weight: .regular)
    /// "Worked 47m 12s" / "Edited 5 files" log lines.
    public static let logLine = rounded(size: 15, weight: .regular)
    /// Artifact card titles ("Parallel execution plan", "To-dos 8/8").
    public static let cardTitle = rounded(size: 16, weight: .semibold)
    /// Pill button labels ("View PR", "Squash & Merge").
    public static let pillLabel = rounded(size: 15, weight: .medium)
    /// PR/diff page title (bold wrapped headline + "#26" number).
    public static let prTitle = rounded(size: 24, weight: .bold)
    /// Status pill row and file diffstat text.
    public static let statusPill = rounded(size: 13, weight: .medium)
    /// Diff line numbers and syntax-highlighted source.
    public static let diffLineNumber = mono(size: 12, weight: .regular)
    public static let diffCode = mono(size: 13, weight: .regular)
    /// Evidence / hash blocks in review surfaces.
    public static let evidenceMono = mono(size: 13, weight: .regular)
    /// Version footer ("CURSOR V1.2.0").
    public static let versionFooter = rounded(size: 11, weight: .medium)

    public static func rounded(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    public static func mono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
#endif
