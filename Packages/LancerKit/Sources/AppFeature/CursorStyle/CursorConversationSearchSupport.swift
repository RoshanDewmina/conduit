import Foundation
import LancerCore

/// Pure helpers for conversation search presentation — scoped FTS query shaping,
/// row copy, and highlight ranges. Kept testable without SwiftUI dependencies.
///
/// Extracted verbatim out of the old `CursorSearchOverlay.swift` (whose View half was
/// deleted/rebuilt in the 2026-07-09 shell rebuild) into its own file so
/// `CursorConversationSearchSupportTests` keeps exercising the same logic independent of
/// any specific search overlay view.
public enum CursorConversationSearchSupport {
    public enum Scope: String, CaseIterable, Sendable {
        case all = "All"
        case prompts = "Prompts"
        case responses = "Responses"
        case artifacts = "Artifacts"

        var ftsColumn: String? {
            switch self {
            case .all: return nil
            case .prompts: return "prompt"
            case .responses: return "assistant_text"
            case .artifacts: return "artifact_text"
            }
        }
    }

    public enum Phase: Equatable, Sendable {
        case idle
        case searching
        case results
        case noResults
        case unavailable
    }

    /// Shapes the raw user query for `chat_fts` column scoping without touching
    /// `ChatConversationRepository` — each term is prefixed with the FTS column
    /// name when a scope other than `.all` is selected.
    public static func scopedFTSQuery(rawQuery: String, scope: Scope) -> String {
        let terms = rawQuery
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        guard !terms.isEmpty else { return "" }
        guard let column = scope.ftsColumn else {
            return terms.joined(separator: " ")
        }
        return terms.map { "\(column):\($0)" }.joined(separator: " ")
    }

    public static func repoName(from cwd: String) -> String {
        let base = (cwd as NSString).lastPathComponent
        return base.isEmpty ? cwd : base
    }

    /// Repo and/or host context for a search hit — `nil` when nothing real to show.
    public static func contextLine(for conversation: ChatConversation) -> String? {
        let repo = repoName(from: conversation.cwd)
        let host: String? = {
            if let source = conversation.sourceHostName, !source.isEmpty { return source }
            if !conversation.hostName.isEmpty { return conversation.hostName }
            return nil
        }()
        switch (repo.isEmpty, host) {
        case (true, nil): return nil
        case (false, nil): return repo
        case (true, let host?): return host
        case (false, let host?):
            return repo == host ? repo : "\(repo) · \(host)"
        }
    }

    public static func relativeTimestamp(_ date: Date, now: Date = .now) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: now)
    }

    /// Snippet line under the title — omitted when empty or identical to the title.
    public static func displaySnippet(for result: ChatConversationSearchResult) -> String? {
        let snippet = result.snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !snippet.isEmpty else { return nil }
        let title = result.conversation.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if snippet.caseInsensitiveCompare(title) == .orderedSame { return nil }
        return snippet
    }

    /// Case-insensitive ranges of each query term found in `text`.
    public static func matchRanges(in text: String, query: String) -> [Range<String.Index>] {
        let terms = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        guard !terms.isEmpty else { return [] }
        var ranges: [Range<String.Index>] = []
        for term in terms {
            var searchStart = text.startIndex
            while searchStart < text.endIndex,
                  let found = text.range(
                    of: term,
                    options: [.caseInsensitive, .diacriticInsensitive],
                    range: searchStart..<text.endIndex,
                    locale: .current
                  ) {
                ranges.append(found)
                searchStart = found.upperBound
            }
        }
        return ranges.sorted { $0.lowerBound < $1.lowerBound }
    }
}

#if os(iOS)
import SwiftUI
import DesignSystem

extension CursorConversationSearchSupport {
    static func highlightedText(_ text: String, query: String, highlightColor: Color) -> Text {
        let ranges = matchRanges(in: text, query: query)
        guard !ranges.isEmpty else { return Text(text) }
        var attributed = AttributedString(text)
        for range in ranges {
            guard let attrRange = Range(range, in: attributed) else { continue }
            attributed[attrRange].foregroundColor = highlightColor
            attributed[attrRange].font = .body.weight(.semibold)
        }
        return Text(attributed)
    }
}
#endif
