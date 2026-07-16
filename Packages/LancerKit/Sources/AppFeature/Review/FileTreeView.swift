#if os(iOS)
import SwiftUI

/// Lazy repo tree: dirs-first, chevron expand, per-level fetch via ReviewDataSource.
struct FileTreeView: View {
    let conversationID: String
    let dataSource: any ReviewDataSource
    var onSelectFile: (String) -> Void

    @State private var roots: [ReviewTreeNode] = []
    @State private var searchText = ""
    @State private var isLoadingRoot = true
    @State private var loadError: String?
    /// Path → expand failure message (kept while the folder row stays expanded).
    @State private var expandErrorByPath: [String: String] = [:]

    private var displayed: [ReviewTreeNode] {
        ReviewTreeMerge.filter(nodes: roots, query: searchText)
    }

    private var flatRows: [(node: ReviewTreeNode, depth: Int)] {
        flatten(displayed, depth: 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if isLoadingRoot {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let loadError {
                    Text(loadError)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(flatRows, id: \.node.id) { row in
                                treeRow(row.node, depth: row.depth)
                            }
                        }
                    }
                }
            }

            searchBar
        }
        .task { await loadRoot() }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search files", text: $searchText)
                .font(.system(size: 15))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private func treeRow(_ node: ReviewTreeNode, depth: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                if node.isDir {
                    Task { await toggleExpand(node) }
                } else {
                    onSelectFile(node.path)
                }
            } label: {
                HStack(spacing: 8) {
                    Color.clear.frame(width: CGFloat(depth) * 14)
                    if node.isDir {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(node.isExpanded ? 90 : 0))
                            .frame(width: 14)
                    } else {
                        Color.clear.frame(width: 14)
                    }
                    Image(systemName: node.isDir ? "folder.fill" : "doc.text")
                        .font(.system(size: 14))
                        .foregroundStyle(node.isDir ? Color.accentColor : Color.secondary)
                    Text(node.name)
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer()
                    if node.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(node.isDir
                ? "\(node.isExpanded ? "Collapse" : "Expand") folder \(node.name)"
                : "File \(node.name)"))

            if let expandError = expandErrorByPath[node.path] {
                HStack(alignment: .top, spacing: 8) {
                    Color.clear.frame(width: CGFloat(depth) * 14 + 14)
                    InlineRetryBanner(
                        title: "Couldn’t expand folder",
                        message: expandError,
                        retryTitle: "Retry",
                        accessibilityRetryLabel: "Retry expanding \(node.name)"
                    ) {
                        Task { await retryExpand(node) }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            }
        }
    }

    private func flatten(_ nodes: [ReviewTreeNode], depth: Int) -> [(node: ReviewTreeNode, depth: Int)] {
        var rows: [(node: ReviewTreeNode, depth: Int)] = []
        for node in nodes {
            rows.append((node, depth))
            if node.isExpanded, let children = node.children {
                rows.append(contentsOf: flatten(children, depth: depth + 1))
            }
        }
        return rows
    }

    private func loadRoot() async {
        isLoadingRoot = true
        loadError = nil
        do {
            let entries = try await dataSource.tree(conversationID: conversationID, path: "")
            roots = ReviewTreeMerge.nodes(parentPath: "", entries: entries)
        } catch {
            loadError = error.localizedDescription
        }
        isLoadingRoot = false
    }

    private func toggleExpand(_ node: ReviewTreeNode) async {
        if node.isExpanded {
            _ = ReviewTreeMerge.updateNode(path: node.path, in: &roots) { n in
                n.isExpanded = false
            }
            expandErrorByPath.removeValue(forKey: node.path)
            return
        }
        if node.children != nil {
            _ = ReviewTreeMerge.updateNode(path: node.path, in: &roots) { n in
                n.isExpanded = true
            }
            expandErrorByPath.removeValue(forKey: node.path)
            return
        }
        await fetchChildren(for: node)
    }

    private func retryExpand(_ node: ReviewTreeNode) async {
        await fetchChildren(for: node)
    }

    private func fetchChildren(for node: ReviewTreeNode) async {
        expandErrorByPath.removeValue(forKey: node.path)
        _ = ReviewTreeMerge.updateNode(path: node.path, in: &roots) { n in
            n.isLoading = true
            n.isExpanded = true
        }
        do {
            let entries = try await dataSource.tree(conversationID: conversationID, path: node.path)
            ReviewTreeMerge.mergeChildren(path: node.path, entries: entries, into: &roots)
            expandErrorByPath.removeValue(forKey: node.path)
        } catch {
            _ = ReviewTreeMerge.updateNode(path: node.path, in: &roots) { n in
                n.isLoading = false
                // Keep expanded so the inline error stays visible with Retry.
                n.isExpanded = true
                if n.children == nil {
                    n.children = []
                }
            }
            expandErrorByPath[node.path] = error.localizedDescription
        }
    }
}
#endif
