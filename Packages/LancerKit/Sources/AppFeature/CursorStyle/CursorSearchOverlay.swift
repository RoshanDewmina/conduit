#if os(iOS)
import SwiftUI
import DesignSystem

/// Full-screen Cursor-style search overlay: header with a close button and
/// centered "Search" title (`CursorBottomSheetContainer`'s chrome, stretched
/// to fill the presentation rather than a compact drawer height), an
/// auto-focused `CursorSearchField`, a horizontally scrollable row of
/// repo-filter chips, and a results list of `CursorThreadRow`s filtered by
/// both the selected repo chip and the search text. Static seed data only —
/// no daemon/network wiring.
public struct CursorSearchOverlay: View {
    @State private var searchText = ""
    @State private var selectedFilter = "All"
    @FocusState private var isSearchFieldFocused: Bool

    private let onClose: () -> Void
    private let onSelectResult: (String) -> Void

    public init(
        onClose: @escaping () -> Void = {},
        onSelectResult: @escaping (String) -> Void = { _ in }
    ) {
        self.onClose = onClose
        self.onSelectResult = onSelectResult
    }

    private var results: [CursorThreadRowModel] {
        [
            CursorThreadRowModel(
                title: "Fix onboarding pairing flow",
                repoName: "lancer-ios",
                isActive: true,
                statusLine: .checksPassed(diffAdded: 142, diffRemoved: 18)
            ),
            CursorThreadRowModel(
                title: "Update relay retry backoff",
                repoName: "push-backend",
                isActive: false,
                statusLine: .checksPassed(diffAdded: 31, diffRemoved: 4)
            ),
            CursorThreadRowModel(
                title: "Review Siri intent donations",
                repoName: "lancer-ios",
                isActive: false,
                statusLine: .noChanges
            ),
            CursorThreadRowModel(
                title: "Harden approval risk-tier floor",
                repoName: "push-backend",
                isActive: false,
                statusLine: .checksPassed(diffAdded: 96, diffRemoved: 22)
            ),
            CursorThreadRowModel(
                title: "Fix relay reconnect race",
                repoName: "lancer-ios",
                isActive: false,
                statusLine: .checksPassed(diffAdded: 54, diffRemoved: 11)
            )
        ]
    }

    /// Repo names in first-seen order, used to seed one filter chip per repo.
    private var repoNames: [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        for result in results where !seen.contains(result.repoName) {
            seen.insert(result.repoName)
            ordered.append(result.repoName)
        }
        return ordered
    }

    private var filterOptions: [String] {
        ["All"] + repoNames
    }

    private var filteredResults: [CursorThreadRowModel] {
        results
            .filter { selectedFilter == "All" || $0.repoName == selectedFilter }
            .filter { searchText.isEmpty || $0.title.localizedCaseInsensitiveContains(searchText) }
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

                filterChipsRow
                    .padding(.top, 14)
                    .padding(.bottom, 8)

                resultsList
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity)
        .environment(\.cursorScheme, .light)
        .onAppear { isSearchFieldFocused = true }
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

    private var resultsList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(filteredResults) { model in
                    Button(action: { onSelectResult(model.title) }) {
                        CursorThreadRow(model: model, showRepoTag: true)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
#endif
