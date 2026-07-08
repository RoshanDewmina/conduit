#if os(iOS)
import SwiftUI
import DesignSystem
import LancerCore

/// Full-screen Cursor-style search overlay: header with a close button and
/// centered "Search" title (`CursorBottomSheetContainer`'s chrome, stretched
/// to fill the presentation rather than a compact drawer height), an
/// auto-focused `CursorSearchField`, a horizontally scrollable row of
/// repo-filter chips, and a results list of `CursorThreadRow`s. Real
/// full-text search over conversation history via `liveBridge.onSearch`
/// (`chat_fts`) — previously filtered a 5-row hardcoded list client-side and
/// never searched anything real (2026-07-07).
public struct CursorSearchOverlay: View {
    @Environment(\.cursorShellLiveBridge) private var liveBridge
    @Environment(\.cursorScheme) private var cursorScheme
    @State private var searchText = ""
    @State private var selectedFilter = "All"
    @State private var results: [ChatConversationSearchResult] = []
    @State private var searchTask: Task<Void, Never>?
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

    private func repoName(for conversation: ChatConversation) -> String {
        let last = (conversation.cwd as NSString).lastPathComponent
        return last.isEmpty ? conversation.cwd : last
    }

    /// Repo names in first-seen order, used to seed one filter chip per repo.
    private var repoNames: [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        for result in results {
            let name = repoName(for: result.conversation)
            if !seen.contains(name) {
                seen.insert(name)
                ordered.append(name)
            }
        }
        return ordered
    }

    private var filterOptions: [String] {
        ["All"] + repoNames
    }

    private var filteredResults: [ChatConversationSearchResult] {
        guard selectedFilter != "All" else { return results }
        return results.filter { repoName(for: $0.conversation) == selectedFilter }
    }

    private func runSearch(_ query: String) {
        searchTask?.cancel()
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            results = []
            return
        }
        searchTask = Task {
            // Debounce so every keystroke doesn't fire its own FTS query.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let matches = await liveBridge?.onSearch?(query) ?? []
            guard !Task.isCancelled else { return }
            results = matches
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

                if !repoNames.isEmpty {
                    filterChipsRow
                        .padding(.top, 14)
                        .padding(.bottom, 8)
                }

                resultsList
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
    }

    private var filterChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: CursorMetrics.pillButtonSpacing) {
                ForEach(filterOptions, id: \.self) { filter in
                    CursorPillButton(
                        title: filter,
                        style: selectedFilter == filter ? .primary : .secondary,
                        action: { selectedFilter = filter }
                    )
                }
            }
            .padding(.horizontal, CursorMetrics.rowHorizontalPadding)
        }
    }

    @ViewBuilder
    private var resultsList: some View {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            emptyState("Search your conversation history")
        } else if filteredResults.isEmpty {
            emptyState("No matches for \u{201c}\(searchText)\u{201d}")
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(filteredResults) { result in
                        Button(action: { onSelectResult(result.conversation.id, result.conversation.title) }) {
                            CursorThreadRow(
                                model: CursorThreadRowModel(
                                    id: UUID(uuidString: result.conversation.id) ?? UUID(),
                                    title: result.conversation.title,
                                    repoName: repoName(for: result.conversation),
                                    isActive: false,
                                    statusLine: .noChanges
                                ),
                                showRepoTag: true
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(CursorType.bodyText)
            .foregroundColor(CursorColors.resolve(cursorScheme).secondaryText)
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
    }
}
#endif
