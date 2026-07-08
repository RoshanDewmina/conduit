#if os(iOS)
import SwiftUI
import DesignSystem
import LancerCore

/// Visual clone of Cursor's mobile PR detail screen (IMG_2411 light /
/// IMG_2424+2426 dark): header with back/link/menu actions, the PR title +
/// number, an Open/Merged status row with diffstat + file/commit counts, a
/// "Ready to Merge" card with a full-width merge CTA, and a file list that
/// pushes into `CursorDiffView` per file. Tapping "Commits" presents
/// `CursorCommitsSheet`.
///
/// The real Git/PR data source (open/merged state, commits, per-file diffs)
/// is not wired into `CursorShellLiveBridge` for V1 yet — see
/// `docs/plans/2026-07-08-lancer-layer-4-6-lane-proposal.md`. This view keeps
/// the existing honest deferred state as its default (no fake PR ever shown
/// live), and — mirroring `CursorWorkThreadView`'s `LANCER_CURSOR_MOCK_RECEIPT`
/// seam — renders the full pixel-close layout from a `Model` when one is
/// supplied (DEBUG-only demo data below, used by screenshots/UI tests).
public struct CursorPRDetailView: View {
    /// Everything the PR screen needs to render, decoupled from any one data
    /// source so a future live wiring pass can construct this directly from
    /// `lancerd`'s GitHub adapter instead of changing this view's body.
    public struct Model: Sendable {
        public struct File: Identifiable, Sendable, Hashable {
            public let id: String
            public let path: String
            public let additions: Int
            public let deletions: Int
            public let diffLines: [CursorDiffLine]

            public init(path: String, additions: Int, deletions: Int, diffLines: [CursorDiffLine] = []) {
                self.id = path
                self.path = path
                self.additions = additions
                self.deletions = deletions
                self.diffLines = diffLines
            }
        }

        public let title: String
        public let number: Int
        public let isMerged: Bool
        public let allChecksPassed: Bool
        public let commits: [CursorCommitsSheet.Commit]
        public let files: [File]

        public var additions: Int { files.reduce(0) { $0 + $1.additions } }
        public var deletions: Int { files.reduce(0) { $0 + $1.deletions } }

        public init(
            title: String,
            number: Int,
            isMerged: Bool,
            allChecksPassed: Bool,
            commits: [CursorCommitsSheet.Commit],
            files: [File]
        ) {
            self.title = title
            self.number = number
            self.isMerged = isMerged
            self.allChecksPassed = allChecksPassed
            self.commits = commits
            self.files = files
        }
    }

    @Environment(\.cursorScheme) private var cursorScheme

    private let onBack: () -> Void
    private let model: Model?

    @State private var commitsSheetPresented = false
    @State private var pushedFile: Model.File?
    @State private var copiedToastText: String?

    private var colors: CursorColors { CursorColors.resolve(cursorScheme) }

    public init(onBack: @escaping () -> Void = {}, model: Model? = nil) {
        self.onBack = onBack
        #if DEBUG
        self.model = model ?? Self.debugModel
        #else
        self.model = model
        #endif
    }

    public var body: some View {
        Group {
            if let model {
                populated(model)
            } else {
                deferredState
            }
        }
        .background(colors.background.ignoresSafeArea())
        .overlay(alignment: .top) {
            if let copiedToastText {
                CursorCopiedToast(text: copiedToastText)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .navigationDestination(item: $pushedFile) { file in
            CursorFileDiffScreen(
                fileName: (file.path as NSString).lastPathComponent,
                fullPath: file.path,
                additions: file.additions,
                deletions: file.deletions,
                lines: file.diffLines,
                onBack: { pushedFile = nil }
            )
        }
        .sheet(isPresented: $commitsSheetPresented) {
            if let model {
                CursorCommitsSheet(
                    commits: model.commits,
                    onDismiss: { commitsSheetPresented = false }
                )
                .environment(\.cursorScheme, cursorScheme)
            }
        }
    }

    // MARK: Deferred (no real PR data source yet)

    private var deferredState: some View {
        VStack(spacing: 0) {
            header(menu: false)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Ship history not built yet")
                        .font(CursorType.pageTitle)
                        .foregroundColor(colors.primaryText)
                    Text("Lancer does not yet have a real PR, inline diff, or GitHub status data source in the live Cursor shell. This screen is intentionally withheld from the default navigation path until it can show real host data.")
                        .font(CursorType.bodyText)
                        .foregroundColor(colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, CursorMetrics.pageTitleLeadingPadding)
                .padding(.top, CursorMetrics.pageTitleTopPadding)
                .padding(.bottom, 24)
            }
        }
    }

    // MARK: Populated (IMG_2411 / IMG_2424 / IMG_2426)

    private func populated(_ model: Model) -> some View {
        VStack(spacing: 0) {
            header(menu: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    titleBlock(model)
                    statusRow(model)
                    readyToMergeCard(model)
                    fileListSection(model)
                }
                .padding(.horizontal, CursorMetrics.pageTitleLeadingPadding)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
        }
    }

    // MARK: Header

    private func header(menu: Bool) -> some View {
        HStack(spacing: CursorMetrics.headerSpacing) {
            CursorIconButton(systemImageName: "chevron.left", action: onBack)
            Spacer()
            if menu {
                CursorIconButton(systemImageName: "link", action: copyLink)
                    .accessibilityIdentifier("pr-detail-copy-link")
                overflowMenu
            }
        }
        .padding(.horizontal, CursorMetrics.headerHorizontalPadding)
        .padding(.top, CursorMetrics.headerTopPadding)
    }

    /// Row-13 PR "…" menu (IMG_2429): Open in GitHub, Close PR (red). Neither
    /// is wired to a live action — no GitHub adapter exists in `lancerd` yet
    /// (see file doc comment); present for pixel-closeness, reported as a gap.
    private var overflowMenu: some View {
        Menu {
            Button { } label: { Label("Open in GitHub", systemImage: "arrow.up.right") }
            Divider()
            Button(role: .destructive) { } label: { Label("Close PR", systemImage: "xmark.circle") }
        } label: {
            ZStack {
                Circle()
                    .fill(colors.iconButtonBackground)
                    .overlay(Circle().stroke(colors.iconButtonBorder, lineWidth: 1))
                    .frame(width: CursorMetrics.headerButtonDiameter, height: CursorMetrics.headerButtonDiameter)
                Image(systemName: "ellipsis")
                    .font(.system(size: CursorMetrics.headerIconSize, weight: .medium))
                    .foregroundColor(colors.primaryText)
            }
        }
        .accessibilityIdentifier("pr-detail-overflow-menu")
    }

    private func copyLink() {
        #if os(iOS)
        UIPasteboard.general.string = "https://github.com/example/example/pull/\(model?.number ?? 0)"
        #endif
        withAnimation(.easeInOut(duration: 0.2)) { copiedToastText = "Copied Link" }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1600))
            withAnimation(.easeInOut(duration: 0.2)) { copiedToastText = nil }
        }
    }

    // MARK: Title block

    private func titleBlock(_ model: Model) -> some View {
        (
            Text(model.title)
                .foregroundColor(colors.primaryText)
            + Text(" #\(model.number)")
                .foregroundColor(colors.mutedText)
        )
        .font(CursorType.prTitle)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Status row

    private func statusRow(_ model: Model) -> some View {
        HStack(spacing: 6) {
            CursorStatusBadge(
                kind: model.isMerged ? .merged : .open,
                label: model.isMerged ? "Merged" : "Open"
            )
            CursorDiffStatText(added: model.additions, removed: model.deletions, font: CursorType.rowSecondary)
            Text("· \(model.files.count) File\(model.files.count == 1 ? "" : "s")")
                .font(CursorType.rowSecondary)
                .foregroundColor(colors.secondaryText)
            Divider().frame(height: 12)
            Button {
                commitsSheetPresented = true
            } label: {
                Text("\(model.commits.count) Commit\(model.commits.count == 1 ? "" : "s")")
                    .font(CursorType.rowSecondary)
                    .foregroundColor(colors.secondaryText)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("pr-detail-commits-link")
        }
    }

    // MARK: Ready to Merge card

    private func readyToMergeCard(_ model: Model) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ready to Merge")
                .font(CursorType.cardTitle)
                .foregroundColor(colors.primaryText)

            if model.allChecksPassed {
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(colors.successGreen)
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(colors.mergeButtonText)
                    }
                    .frame(width: CursorMetrics.checkDotDiameter, height: CursorMetrics.checkDotDiameter)
                    Text("All Checks Passed")
                        .font(CursorType.rowTitle)
                        .foregroundColor(colors.primaryText)
                }
            }

            // Merge-from-phone has no live capability anywhere in Lancer (see
            // `CursorShipActionSheet`'s doc comment: "a permanent, separate,
            // not-yet-designed gate"). Rendered per the reference for pixel
            // parity, disabled so it cannot imply a capability that doesn't
            // exist yet.
            CursorPillButton(title: "Squash & Merge", style: .success, fullWidth: true, action: {})
                .disabled(true)
                .opacity(0.55)
                .accessibilityIdentifier("pr-detail-squash-merge")
        }
        .padding(CursorMetrics.cardPadding)
        .background(colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: CursorMetrics.cardCornerRadius, style: .continuous))
    }

    // MARK: File list

    private func fileListSection(_ model: Model) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(model.files.count) File\(model.files.count == 1 ? "" : "s")")
                .font(CursorType.sectionHeader)
                .foregroundColor(colors.secondaryText)
                .padding(.bottom, 6)

            VStack(spacing: 0) {
                ForEach(Array(model.files.enumerated()), id: \.element.id) { index, file in
                    Button {
                        pushedFile = file
                    } label: {
                        VStack(spacing: 0) {
                            HStack(spacing: CursorMetrics.rowSpacing) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(colors.mutedText)
                                Text((file.path as NSString).lastPathComponent)
                                    .font(CursorType.rowTitle)
                                    .foregroundColor(colors.primaryText)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer(minLength: 8)
                                CursorDiffStatText(added: file.additions, removed: file.deletions)
                            }
                            .padding(.horizontal, CursorMetrics.rowHorizontalPadding)
                            .padding(.vertical, CursorMetrics.rowVerticalPadding)
                            if index < model.files.count - 1 {
                                Rectangle()
                                    .fill(colors.hairline)
                                    .frame(height: CursorMetrics.rowHairlineHeight)
                                    .padding(.leading, CursorMetrics.rowHairlineLeadingInsetWithIcon)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("pr-detail-file-row-\(index)")
                }
            }
            .background(colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: CursorMetrics.cardCornerRadius, style: .continuous))
        }
    }

    #if DEBUG
    /// Demo data for screenshots/UI tests — mirrors IMG_2411/2424/2426
    /// (real Cursor PR #33, "Brainstorm canvas: mobile agent mission control
    /// wireframes"). Only used when no live `Model` is supplied and the app
    /// is a DEBUG build; the shipping Release build always falls back to
    /// `deferredState` until this is wired to a real GitHub adapter.
    static let debugModel = Model(
        title: "Brainstorm canvas: mobile agent\nmission control wireframes",
        number: 33,
        isMerged: ProcessInfo.processInfo.environment["LANCER_CURSOR_PR_MERGED"] == "1",
        allChecksPassed: true,
        commits: [
            CursorCommitsSheet.Commit(
                title: "Add mobile agent brainstorm wireframe canvas",
                author: "Cursor Agent",
                added: 657,
                removed: 0,
                relativeTime: "20h"
            ),
            CursorCommitsSheet.Commit(
                title: "Compile full mission-control brainstorm into one canvas",
                author: "Cursor Agent",
                added: 303,
                removed: 499,
                relativeTime: "19h"
            )
        ],
        files: [
            Model.File(
                path: "mobile-agent-brainstorm.canvas.tsx",
                additions: 461,
                deletions: 0,
                diffLines: [
                    CursorDiffLine(oldNumber: nil, newNumber: 1, text: "/**", kind: .added),
                    CursorDiffLine(oldNumber: nil, newNumber: 2, text: " * Mobile Agent Mission Control — FULL brainstorm", kind: .added),
                    CursorDiffLine(oldNumber: nil, newNumber: 3, text: " * Sessions: Cursor brainstorm · Fable ideas", kind: .added),
                    CursorDiffLine(oldNumber: nil, newNumber: 4, text: " * Open in Cursor Canvas panel", kind: .added),
                    CursorDiffLine(oldNumber: nil, newNumber: 5, text: " */", kind: .added),
                    CursorDiffLine(oldNumber: 12, newNumber: 6, text: "import {", kind: .unchanged),
                    CursorDiffLine(oldNumber: 13, newNumber: 7, text: "  BarChart,", kind: .unchanged),
                    CursorDiffLine(oldNumber: 14, newNumber: 8, text: "  Button,", kind: .unchanged),
                    CursorDiffLine(oldNumber: nil, newNumber: 9, text: "  Callout,", kind: .added),
                    CursorDiffLine(oldNumber: 15, newNumber: nil, text: "  CardOld,", kind: .removed)
                ]
            )
        ]
    )
    #endif
}
#endif
