#if os(iOS)
import SwiftUI

/// Codex-mobile review sheet: Modified diffs + All Files tree, line-comment attach.
public struct ReviewSheetView: View {
    public enum Scope: Equatable, Sendable {
        case turn(turnID: String)
        case session
    }

    let conversationID: String
    let scope: Scope
    let dataSource: any ReviewDataSource
    var onAttachComment: (QueuedReviewComment) -> Void
    /// Optional PR identity for the session branch. Absent → show "PR not opened yet".
    var prState: ReviewPRState?
    /// Host-backed Open PR. Nil → menu item disabled (no Review-sheet RPC wired yet).
    var onOpenPR: (() -> Void)?
    /// Host-backed Close PR. Nil → menu item disabled (no close RPC on the client surface).
    var onClosePR: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var tab: Tab = .modified
    @State private var summary: RepoDiffSummary?
    @State private var fileDiffs: [String: RepoFileDiff] = [:]
    @State private var fileDiffErrors: [String: String] = [:]
    @State private var loadingPaths: Set<String> = []
    @State private var expandAll = true
    @State private var isLoadingSummary = true
    @State private var loadError: String?
    @State private var pendingComment: PendingComment?
    @State private var viewerPath: String?

    private enum Tab: String, CaseIterable {
        case modified = "Modified"
        case allFiles = "All Files"
    }

    private struct PendingComment: Identifiable {
        let id = UUID()
        let path: String
        let line: Int
        let lineText: String
    }

    public init(
        conversationID: String,
        scope: Scope,
        dataSource: any ReviewDataSource = FixtureReviewDataSource.shared,
        onAttachComment: @escaping (QueuedReviewComment) -> Void = { _ in },
        prState: ReviewPRState? = nil,
        onOpenPR: (() -> Void)? = nil,
        onClosePR: (() -> Void)? = nil
    ) {
        self.conversationID = conversationID
        self.scope = scope
        self.dataSource = dataSource
        self.onAttachComment = onAttachComment
        self.prState = prState
        self.onOpenPR = onOpenPR
        self.onClosePR = onClosePR
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                if !hasOpenPR {
                    ReviewPRHintCard()
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
                Picker("Mode", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                Group {
                    switch tab {
                    case .modified:
                        modifiedContent
                    case .allFiles:
                        FileTreeView(
                            conversationID: conversationID,
                            dataSource: dataSource,
                            onSelectFile: { viewerPath = $0 }
                        )
                    }
                }
            }
            .background(Color(.systemBackground))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Color(.secondarySystemFill)))
                    }
                    .accessibilityLabel(Text("Close"))
                }
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        prActionsMenu
                        Button {
                            withAnimation {
                                expandAll.toggle()
                            }
                        } label: {
                            Image(systemName: expandAll ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .accessibilityLabel(Text(expandAll ? "Collapse all" : "Expand all"))
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDragIndicator(.visible)
        .task { await loadSummary() }
        .sheet(item: $pendingComment) { pending in
            AddCommentSheet(
                path: pending.path,
                line: pending.line,
                lineText: pending.lineText,
                onCancel: { pendingComment = nil },
                onAttach: { comment in
                    onAttachComment(comment)
                    pendingComment = nil
                }
            )
        }
        .sheet(item: Binding(
            get: { viewerPath.map { ViewerPath(path: $0) } },
            set: { viewerPath = $0?.path }
        )) { item in
            FileViewerView(
                conversationID: conversationID,
                path: item.path,
                dataSource: dataSource
            )
        }
    }

    private var hasOpenPR: Bool { prState?.hasOpenPR == true }

    private var canOpenPR: Bool { onOpenPR != nil && !hasOpenPR }

    private var canOpenInGitHub: Bool { prState?.url != nil }

    private var canClosePR: Bool { onClosePR != nil && hasOpenPR }

    private var prActionsMenu: some View {
        Menu {
            Section {
                Button {
                    onOpenPR?()
                } label: {
                    Label("Open PR…", systemImage: "plus.circle")
                }
                .disabled(!canOpenPR)

                Button {
                    if let url = prState?.url {
                        openURL(url)
                    }
                } label: {
                    Label("Open in GitHub", systemImage: "safari")
                }
                .disabled(!canOpenInGitHub)

                Button(role: .destructive) {
                    onClosePR?()
                } label: {
                    Label("Close PR", systemImage: "xmark.circle")
                }
                .disabled(!canClosePR)
            } footer: {
                if showsPRActionsFootnote {
                    Text(prActionsFootnote)
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 14, weight: .medium))
        }
        .accessibilityLabel(Text("PR actions"))
        .accessibilityIdentifier("review-pr-actions-menu")
    }

    private var showsPRActionsFootnote: Bool {
        !canOpenPR || !canClosePR || (prState?.url == nil && onOpenPR == nil)
    }

    private var prActionsFootnote: String {
        // SSH GitClient.createPullRequest / agent.git.ship(openPR:) exist, but the
        // Review sheet has no AppFeature→host PR create/close/status binding yet.
        // Close has no client RPC. Open-in-GitHub needs a known PR URL.
        if hasOpenPR, prState?.url != nil, onClosePR == nil {
            return "Close PR needs a host RPC — not available yet."
        }
        if canOpenInGitHub, onOpenPR == nil, onClosePR == nil {
            return "Open/Close PR need host RPCs — not wired to this sheet yet."
        }
        return "PR actions need host RPCs — not wired to this sheet yet."
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(summary?.titleLabel ?? "Files changed")
                .font(.system(size: 20, weight: .bold))
            if let summary {
                Text(summary.countsLabel)
                    .font(.system(size: 15, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var modifiedContent: some View {
        if isLoadingSummary {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let loadError {
            Text(loadError)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let summary, summary.hasChanges {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(summary.files) { file in
                        Section {
                            DiffFileSection(
                                file: file,
                                fileDiff: fileDiffs[file.path],
                                isLoading: loadingPaths.contains(file.path),
                                loadError: fileDiffErrors[file.path],
                                expandAll: expandAll,
                                onOpenViewer: { viewerPath = file.path },
                                onComment: { row in
                                    guard let line = row.displayLineNumber else { return }
                                    pendingComment = PendingComment(
                                        path: file.path,
                                        line: line,
                                        lineText: row.text
                                    )
                                }
                            )
                            .task(id: file.path) {
                                await loadFileDiff(path: file.path)
                            }
                        }
                    }
                }
                .padding(.bottom, 24)
            }
        } else {
            Text("No file changes")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func loadSummary() async {
        isLoadingSummary = true
        loadError = nil
        do {
            switch scope {
            case .turn(let turnID):
                summary = try await dataSource.turnDiff(
                    conversationID: conversationID,
                    turnID: turnID
                )
            case .session:
                summary = try await dataSource.sessionDiff(conversationID: conversationID)
            }
        } catch {
            loadError = error.localizedDescription
        }
        isLoadingSummary = false
    }

    private func loadFileDiff(path: String) async {
        guard fileDiffs[path] == nil, fileDiffErrors[path] == nil, !loadingPaths.contains(path) else { return }
        loadingPaths.insert(path)
        let turnID: String? = {
            if case .turn(let id) = scope { return id }
            return nil
        }()
        do {
            let diff = try await dataSource.fileDiff(
                conversationID: conversationID,
                path: path,
                turnID: turnID
            )
            fileDiffs[path] = diff
            fileDiffErrors.removeValue(forKey: path)
        } catch {
            fileDiffErrors[path] = error.localizedDescription
        }
        loadingPaths.remove(path)
    }
}

private struct ViewerPath: Identifiable {
    let path: String
    var id: String { path }
}
#endif
