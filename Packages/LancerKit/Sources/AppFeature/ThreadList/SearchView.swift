#if os(iOS)
import SwiftUI

/// Section 5 of the frontend rebuild: a faithful, Apple-native recreation of
/// the Cursor-mobile "Search" sheet (owner reference screenshot `IMG_2417`).
/// Presented from the Workspaces root's magnifying-glass button (and from
/// `ThreadListView`'s top-bar search icon). Visual-only for this milestone —
/// the search field accepts typing but doesn't filter, and the filter chips
/// are selectable but don't affect the (static) result list.
/// System `SF Symbols` + semantic colors only, no DesignSystem module.
public struct SearchView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedFilter: SearchFilter = .all

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            RepoSheetHeader(title: "Search") { dismiss() }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 12)

            searchField
                .padding(.horizontal, 20)
                .padding(.bottom, 14)

            filterChips
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Self.results) { thread in
                        ThreadListRow(thread: thread, showsRepoName: true)
                        Divider()
                            .padding(.leading, 40)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("Agents, repos...", text: $searchText)
                .font(.system(size: 16))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel(Text("Clear search"))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Capsule().fill(Color(.secondarySystemBackground)))
    }

    private var filterChips: some View {
        HStack(spacing: 10) {
            ForEach(SearchFilter.allCases) { filter in
                filterChip(filter)
            }
            Spacer(minLength: 0)
        }
    }

    private func filterChip(_ filter: SearchFilter) -> some View {
        Button {
            selectedFilter = filter
        } label: {
            Text(filter.title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(selectedFilter == filter ? Color(.systemBackground) : .primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(selectedFilter == filter ? Color.primary : Color(.secondarySystemBackground))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Static sample data

    fileprivate static let results: [ThreadRow] = [
        ThreadRow(title: "Fix onboarding flow", status: .checksPassed, diffStat: "+142 -18", repoName: "conduit"),
        ThreadRow(title: "Update README", status: .merged, diffStat: nil, repoName: "conduit"),
        ThreadRow(title: "Refactor auth module", status: .merged, diffStat: "+89 -34", repoName: "conduit"),
        ThreadRow(title: "Add dark mode toggle", status: .checksPassed, diffStat: "+212 -6", repoName: "personal-web"),
        ThreadRow(title: "Investigate flaky CI job", status: .noChanges, diffStat: nil, repoName: "conduit"),
        ThreadRow(title: "Clean up test fixtures", status: .merged, diffStat: "+54 -201", repoName: "personal-web"),
        ThreadRow(title: "Optimize image loading", status: .noChanges, diffStat: nil, repoName: "personal-web"),
    ]
}

/// Filter chip state — visually selectable, has no effect on the (static)
/// result list.
enum SearchFilter: CaseIterable, Identifiable {
    case all
    case conduit
    case personalWeb

    var id: Self { self }

    var title: String {
        switch self {
        case .all: return "All"
        case .conduit: return "conduit"
        case .personalWeb: return "personal-web"
        }
    }
}

#Preview {
    SearchView()
}
#endif
