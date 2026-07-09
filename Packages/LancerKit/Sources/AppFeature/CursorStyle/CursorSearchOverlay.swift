#if os(iOS)
import SwiftUI
import LancerCore

/// Full-text search via `liveBridge.onSearch` (`chat_fts`).
public struct CursorSearchOverlay: View {
    @Environment(\.cursorShellLiveBridge) private var liveBridge
    @State private var searchText = ""
    @State private var selectedScope = CursorConversationSearchSupport.Scope.all
    @State private var results: [ChatConversationSearchResult] = []
    @State private var phase = CursorConversationSearchSupport.Phase.idle
    @State private var searchTask: Task<Void, Never>?
    @State private var searchGeneration = 0
    @FocusState private var isSearchFieldFocused: Bool

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
        let scopedQuery = CursorConversationSearchSupport.scopedFTSQuery(rawQuery: trimmed, scope: selectedScope)
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
        NavigationStack {
            List {
                Section {
                    TextField("Search", text: $searchText)
                        .focused($isSearchFieldFocused)
                        .onChange(of: searchText) { _, newValue in runSearch(newValue) }
                    Picker("Scope", selection: $selectedScope) {
                        ForEach(CursorConversationSearchSupport.Scope.allCases, id: \.self) { scope in
                            Text(scope.rawValue).tag(scope)
                                .accessibilityIdentifier("search-scope-\(scope.rawValue)")
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedScope) { _, _ in
                        guard !trimmedQuery.isEmpty else { return }
                        runSearch(searchText)
                    }
                }

                switch phase {
                case .idle:
                    Text("Search prompts, responses, and artifacts")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("search-idle-hint")
                case .searching:
                    HStack {
                        ProgressView()
                        Text("Searching…")
                    }
                    .accessibilityIdentifier("search-progress")
                case .unavailable:
                    Text("Search isn’t available right now.")
                        .accessibilityIdentifier("search-unavailable")
                    Button("Try again") { runSearch(searchText) }
                        .accessibilityIdentifier("search-retry")
                case .noResults:
                    Text("No matches for “\(searchText)”")
                        .accessibilityIdentifier("search-no-results")
                case .results:
                    ForEach(results) { result in
                        Button {
                            onSelectResult(result.conversation.id, result.conversation.title)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(result.conversation.title)
                                if let snippet = CursorConversationSearchSupport.displaySnippet(for: result) {
                                    Text(snippet).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                                }
                                if let context = CursorConversationSearchSupport.contextLine(for: result.conversation) {
                                    Text(context).font(.caption2).foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .accessibilityIdentifier("search-result-\(result.conversation.id)")
                    }
                }
            }
            .navigationTitle("Search")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onClose)
                }
            }
        }
        .onAppear {
            isSearchFieldFocused = true
            if let initialQuery, !initialQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                searchText = initialQuery
                runSearch(initialQuery)
            }
        }
    }
}
#endif
