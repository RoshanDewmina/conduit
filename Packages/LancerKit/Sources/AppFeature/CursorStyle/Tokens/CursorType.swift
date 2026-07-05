#if os(iOS)
import SwiftUI

/// Font definitions for the Cursor-style look. Fonts don't need light/dark
/// variants — only color does, via `CursorColors`.
public enum CursorType {
    public static let pageTitle = Font.system(size: 32, weight: .bold)
    public static let sheetTitle = Font.system(size: 17, weight: .semibold)
    public static let rowTitle = Font.system(size: 17, weight: .regular)
    public static let rowSecondary = Font.system(size: 13, weight: .regular)
    public static let sectionHeader = Font.system(size: 13, weight: .regular)
    public static let composerPlaceholder = Font.system(size: 16, weight: .regular)

    /// Work Thread narration prose (IMG_2360/2361 body text).
    public static let bodyText = Font.system(size: 16, weight: .regular)
    /// Bold inline labels within narration (e.g. "Why:", "Worktree locations").
    public static let bodyEmphasis = Font.system(size: 16, weight: .semibold)
    /// Inline code-styled file-path chips.
    public static let inlineCode = Font.system(size: 15, weight: .regular, design: .monospaced)
    /// "Worked 47m 12s" / "Edited 5 files" log lines.
    public static let logLine = Font.system(size: 15, weight: .regular)
    /// Artifact card titles ("Parallel execution plan", "To-dos 8/8").
    public static let cardTitle = Font.system(size: 16, weight: .semibold)
    /// Pill button labels ("View PR", "Mark Ready").
    public static let pillLabel = Font.system(size: 15, weight: .medium)
    /// PR/diff page title (bold wrapped headline + "#26" number).
    public static let prTitle = Font.system(size: 24, weight: .bold)
    /// Status pill row (Draft / No Changes / 1 Commit) and file diffstat text.
    public static let statusPill = Font.system(size: 13, weight: .medium)
    /// Diff line numbers and code monospace body.
    public static let diffLineNumber = Font.system(size: 12, weight: .regular, design: .monospaced)
    public static let diffCode = Font.system(size: 13, weight: .regular, design: .monospaced)
}
#endif
