#if os(iOS)
import SwiftUI
import PersistenceKit

/// Search sheet over real `ChatConversationRepository` conversations.
public struct SearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WorkspaceDataStore.self) private var workspaceData
    @State private var searchText = ""
    @State private var selectedFilterCwd: String? = nil
    @State private var results: [ThreadListItem] = []

    public init() {}

    private var filterRepos: [WorkspaceRepo] { workspaceData.repos }

    private var filteredResults: [ThreadListItem] {
        guard let selectedFilterCwd else { return results }
        let roots = filterRepos.map(\.cwd)
        guard let selectedBucket = WorkspaceRepoCatalog.bucketKey(
            forCwd: selectedFilterCwd,
            among: roots
        ) else { return [] }
        let selectedKey = WorkspaceRepoCatalog.pathKey(selectedBucket)
        return results.filter { item in
            guard let bucket = WorkspaceRepoCatalog.bucketKey(forCwd: item.cwd, among: roots) else {
                return false
            }
            return WorkspaceRepoCatalog.pathKey(bucket) == selectedKey
        }
    }

    public var body: some View {
        NavigationStack {
            content
        }
    }

    private var content: some View {
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

            if filteredResults.isEmpty {
                Text(searchText.isEmpty ? "No threads yet" : "No matching threads")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredResults) { thread in
                            NavigationLink {
                                ThreadDetailView(thread: thread)
                                    .onAppear {
                                        workspaceData.markThreadOpened(thread.id)
                                    }
                            } label: {
                                ThreadListRow(thread: thread, showsRepoName: true)
                            }
                            .buttonStyle(.plain)
                            Divider()
                                .padding(.leading, 40)
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task {
            await workspaceData.refresh()
            await runSearch()
        }
        .onChange(of: searchText) { _, _ in
            Task { await runSearch() }
        }
    }

    private func runSearch() async {
        results = await workspaceData.search(searchText)
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                filterChip(title: "All", cwd: nil)
                ForEach(filterRepos) { repo in
                    filterChip(title: repo.name, cwd: repo.cwd)
                }
            }
        }
    }

    private func filterChip(title: String, cwd: String?) -> some View {
        let isSelected = selectedFilterCwd == cwd
        return Button {
            selectedFilterCwd = cwd
        } label: {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isSelected ? Color(.systemBackground) : .primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(isSelected ? Color.primary : Color(.secondarySystemBackground))
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    let db = try! PersistenceKit.AppDatabase.inMemory()
    SearchView()
        .environment(WorkspaceDataStore(chatRepo: ChatConversationRepository(db)))
}
#endif
