import Foundation

/// Builds a native markdown `AttributedString` for assistant body text.
public enum ChatMarkdownAttributedString: Sendable {
    public static func make(from markdown: String) -> AttributedString {
        let prepared = ChatMarkdownPreprocessor.preprocess(markdown)
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .full
        options.failurePolicy = .returnPartiallyParsedIfPossible

        do {
            return try AttributedString(markdown: prepared, options: options)
        } catch {
            return AttributedString(prepared)
        }
    }

    /// Ranges whose inline presentation intent includes `.code` (for chip styling in the view layer).
    public static func inlineCodeRanges(in attributed: AttributedString) -> [Range<AttributedString.Index>] {
        attributed.runs.compactMap { run in
            guard let intent = run.inlinePresentationIntent,
                  intent.contains(.code)
            else { return nil }
            return run.range
        }
    }
}
