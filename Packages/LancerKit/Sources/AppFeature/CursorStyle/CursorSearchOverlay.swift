import Foundation
import LancerCore

/// Pure helpers for conversation search presentation — scoped FTS query shaping,
/// row copy, and highlight ranges. Kept testable without SwiftUI dependencies.
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

/// Full-screen Cursor-style search overlay: header with a close button and
/// centered "Search" title (`CursorBottomSheetContainer`'s chrome, stretched
/// to fill the presentation rather than a compact drawer height), an
/// auto-focused `CursorSearchField`, scope chips (All / Prompts / Responses /
/// Artifacts), and a results list with matched snippets. Real full-text search
/// over conversation history via `liveBridge.onSearch` (`chat_fts`).
public struct CursorSearchOverlay: View {
    @Environment(\.cursorShellLiveBridge) private var liveBridge
    @Environment(\.cursorScheme) private var cursorScheme
    @State private var searchText = ""
    @State private var selectedScope = CursorConversationSearchSupport.Scope.all
    @State private var results: [ChatConversationSearchResult] = []
    @State private var phase = CursorConversationSearchSupport.Phase.idle
    @State private var searchTask: Task<Void, Never>?
    @State private var searchGeneration = 0
    @FocusState private var isSearchFieldFocused: Bool

    /// Prefilled/auto-run query — set when Siri's `SearchLancerIntent`
    /// navigates here (I2) so the overlay shows the same search it already
    /// spoke a result count for, instead of opening blank.
    private let initialQuery: String?
    private let onClose: () -> Void
    private let onSelectResult: (_ conversationID: String, _ title: String) -> Void

    public init(
        initialQuery: String? = nil,
        onClose: @escaping () -> Void = {},
        onSelectResult: @escaping (_ conversationID: String, _ title: String) -> Void = { _, _ in }
    ) {
        self.initialQuery = initialQuery
        self.onClose = onClose
        self.onSelectResult = onSelectResult
    }

    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func runSearch(_ query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            phase = .idle
            return
        }
        guard liveBridge?.onSearch != nil else {
            results = []
            phase = .unavailable
            return
        }
        phase = .searching
        searchGeneration += 1
        let generation = searchGeneration
        let scopedQuery = CursorConversationSearchSupport.scopedFTSQuery(
            rawQuery: trimmed,
            scope: selectedScope
        )
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, generation == searchGeneration else { return }
            let matches = await liveBridge?.onSearch?(scopedQuery) ?? []
            guard !Task.isCancelled, generation == searchGeneration else { return }
            results = matches
            phase = matches.isEmpty ? .noResults : .results
        }
    }

    public var body: some View {
        CursorBottomSheetContainer(
            title: "Search",
            leadingButton: (systemImageName: "xmark", action: onClose)
        ) {
            VStack(spacing: 0) {
                CursorSearchField(text: $searchText)
                    .focused($isSearchFieldFocused)
                    .padding(.top, 4)
                    .onChange(of: searchText) { _, newValue in runSearch(newValue) }

                scopeChipsRow
                    .padding(.top, 14)
                    .padding(.bottom, 8)

                contentArea
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity)
        .onAppear {
            isSearchFieldFocused = true
            if let initialQuery, !initialQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                searchText = initialQuery
                runSearch(initialQuery)
            }
        }
        .onChange(of: selectedScope) { _, _ in
            guard !trimmedQuery.isEmpty else { return }
            runSearch(searchText)
        }
    }

    private var scopeChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: CursorMetrics.pillButtonSpacing) {
                ForEach(CursorConversationSearchSupport.Scope.allCases, id: \.self) { scope in
                    CursorPillButton(
                        title: scope.rawValue,
                        style: selectedScope == scope ? .primary : .secondary,
                        action: { selectedScope = scope }
                    )
                    .accessibilityIdentifier("search-scope-\(scope.rawValue)")
                }
            }
            .padding(.horizontal, CursorMetrics.rowHorizontalPadding)
        }
    }

    @ViewBuilder
    private var contentArea: some View {
        switch phase {
        case .idle:
            idleState
        case .searching:
            searchingState
        case .unavailable:
            errorState(
                message: "Search isn\u{2019}t available right now.",
                accessibilityID: "search-unavailable"
            )
        case .noResults:
            emptyState(
                "No matches for \u{201c}\(searchText)\u{201d}",
                accessibilityID: "search-no-results"
            )
        case .results:
            resultsList
        }
    }

    private var idleState: some View {
        Text("Search prompts, responses, and artifacts")
            .font(CursorType.bodyText)
            .foregroundColor(CursorColors.resolve(cursorScheme).mutedText)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, CursorMetrics.rowHorizontalPadding)
            .padding(.top, 40)
            .accessibilityIdentifier("search-idle-hint")
    }

    private var searchingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(CursorColors.resolve(cursorScheme).secondaryText)
            Text("Searching\u{2026}")
                .font(CursorType.bodyText)
                .foregroundColor(CursorColors.resolve(cursorScheme).secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
        .accessibilityIdentifier("search-progress")
    }

    private var resultsList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(results) { result in
                    Button {
                        onSelectResult(result.conversation.id, result.conversation.title)
                    } label: {
                        CursorSearchResultRow(
                            result: result,
                            query: trimmedQuery,
                            colors: CursorColors.resolve(cursorScheme)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("search-result-\(result.conversation.id)")
                }
            }
        }
    }

    private func emptyState(_ text: String, accessibilityID: String) -> some View {
        Text(text)
            .font(CursorType.bodyText)
            .foregroundColor(CursorColors.resolve(cursorScheme).secondaryText)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, CursorMetrics.rowHorizontalPadding)
            .padding(.top, 40)
            .accessibilityIdentifier(accessibilityID)
    }

    private func errorState(message: String, accessibilityID: String) -> some View {
        let colors = CursorColors.resolve(cursorScheme)
        return VStack(spacing: 16) {
            Text(message)
                .font(CursorType.bodyText)
                .foregroundColor(colors.secondaryText)
                .multilineTextAlignment(.center)
            Button("Try again") {
                runSearch(searchText)
            }
            .font(CursorType.rowTitle)
            .foregroundColor(colors.primaryText)
            .accessibilityIdentifier("search-retry")
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, CursorMetrics.rowHorizontalPadding)
        .padding(.top, 40)
        .accessibilityIdentifier(accessibilityID)
    }
}

// MARK: - Result row

private struct CursorSearchResultRow: View {
    let result: ChatConversationSearchResult
    let query: String
    let colors: CursorColors

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: CursorMetrics.rowSpacing) {
                VStack(alignment: .leading, spacing: CursorMetrics.threadRowContentSpacing) {
                    Text(result.conversation.title)
                        .font(CursorType.rowTitle)
                        .foregroundColor(colors.primaryText)
                        .lineLimit(2)

                    if let snippet = CursorConversationSearchSupport.displaySnippet(for: result) {
                        CursorConversationSearchSupport.highlightedText(
                            snippet,
                            query: query,
                            highlightColor: colors.primaryText
                        )
                        .font(CursorType.rowSecondary)
                        .foregroundColor(colors.secondaryText)
                        .lineLimit(3)
                    }

                    if let context = CursorConversationSearchSupport.contextLine(for: result.conversation) {
                        Text(context)
                            .font(CursorType.rowSecondary)
                            .foregroundColor(colors.mutedText)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                Text(
                    CursorConversationSearchSupport.relativeTimestamp(
                        result.conversation.lastActivityAt
                    )
                )
                .font(CursorType.rowSecondary)
                .foregroundColor(colors.mutedText)
                .layoutPriority(1)
            }
            .padding(.horizontal, CursorMetrics.rowHorizontalPadding)
            .padding(.vertical, CursorMetrics.rowVerticalPadding)

            Rectangle()
                .fill(colors.hairline)
                .frame(height: CursorMetrics.rowHairlineHeight)
                .padding(.leading, CursorMetrics.rowHorizontalPadding)
        }
        .contentShape(Rectangle())
    }
}
#endif
