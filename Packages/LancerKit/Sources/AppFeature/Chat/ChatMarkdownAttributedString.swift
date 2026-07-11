import Foundation

/// Builds a native markdown `AttributedString` for assistant body text.
public enum ChatMarkdownAttributedString: Sendable {
    public static func make(from markdown: String) -> AttributedString {
        let prepared = ChatMarkdownPreprocessor.preprocess(markdown)
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .full
        options.failurePolicy = .returnPartiallyParsedIfPossible

        do {
            let parsed = try AttributedString(markdown: prepared, options: options)
            // Foundation's markdown parser attaches presentation intents per block but does
            // not emit newline characters between them — `Text` then glues "Systems"+"Beginnings:"
            // into "SystemsBeginnings:". Re-insert separators from those intents.
            return insertingBlockSeparators(into: parsed)
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

    /// Insert `\n\n` (or `\n` between list items) whenever the block-level presentation
    /// intent identity changes, so visual spacing matches markdown structure.
    public static func insertingBlockSeparators(into input: AttributedString) -> AttributedString {
        guard !input.runs.isEmpty else { return input }

        var result = AttributedString()
        var lastBlockID: Int?
        var lastWasListItem = false
        var isFirst = true

        for run in input.runs {
            let info = blockInfo(run.presentationIntent)
            if !isFirst, let id = info.id, id != lastBlockID {
                let separator = (lastWasListItem && info.isListItem) ? "\n" : "\n\n"
                result.append(AttributedString(separator))
            }
            result.append(input[run.range])
            if let id = info.id {
                lastBlockID = id
                lastWasListItem = info.isListItem
            }
            isFirst = false
        }
        return result
    }

    private struct BlockInfo {
        var id: Int?
        var isListItem: Bool
    }

    private static func blockInfo(_ intent: PresentationIntent?) -> BlockInfo {
        guard let intent else { return BlockInfo(id: nil, isListItem: false) }
        var id: Int?
        var isListItem = false
        for component in intent.components {
            switch component.kind {
            case .paragraph, .header, .codeBlock, .blockQuote, .thematicBreak,
                 .unorderedList, .orderedList, .table, .tableHeaderRow, .tableRow:
                id = component.identity
            case .listItem:
                id = component.identity
                isListItem = true
            default:
                continue
            }
        }
        return BlockInfo(id: id, isListItem: isListItem)
    }
}
