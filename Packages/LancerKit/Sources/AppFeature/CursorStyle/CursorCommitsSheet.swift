#if os(iOS)
import SwiftUI
import DesignSystem

/// Row-11 "Commits" bottom sheet (IMG_2428): grabber + X + "Commits" title with
/// a "N Commits → main" subtitle, then a vertical timeline of commits (dot +
/// connector), each with a title, author row (icon + name + green/red diff
/// counts), and a relative time on the right. Presented from `CursorPRDetailView`
/// only (screen-map row 11 — new view, no prior Lancer equivalent).
public struct CursorCommitsSheet: View {
    public struct Commit: Identifiable, Sendable {
        public let id: String
        public let title: String
        public let author: String
        public let added: Int
        public let removed: Int
        public let relativeTime: String

        public init(
            id: String = UUID().uuidString,
            title: String,
            author: String,
            added: Int,
            removed: Int,
            relativeTime: String
        ) {
            self.id = id
            self.title = title
            self.author = author
            self.added = added
            self.removed = removed
            self.relativeTime = relativeTime
        }
    }

    @Environment(\.cursorScheme) private var cursorScheme

    private let commits: [Commit]
    private let targetBranch: String
    private let onDismiss: () -> Void

    public init(commits: [Commit], targetBranch: String = "main", onDismiss: @escaping () -> Void = {}) {
        self.commits = commits
        self.targetBranch = targetBranch
        self.onDismiss = onDismiss
    }

    public var body: some View {
        let colors = CursorColors.resolve(cursorScheme)
        CursorBottomSheetContainer(title: "Commits", leadingButton: (systemImageName: "xmark", action: onDismiss)) {
            VStack(alignment: .leading, spacing: 0) {
                subtitle(colors: colors)
                timeline(colors: colors)
            }
            .padding(.bottom, CursorMetrics.sheetContentBottomPadding)
        }
        .accessibilityIdentifier("commits-sheet")
    }

    private func subtitle(colors: CursorColors) -> some View {
        HStack(spacing: 6) {
            Spacer()
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 12, weight: .medium))
            Text("\(commits.count) Commit\(commits.count == 1 ? "" : "s")")
            Image(systemName: "arrow.right")
                .font(.system(size: 11, weight: .semibold))
            Text(targetBranch)
            Spacer()
        }
        .font(CursorType.rowSecondary)
        .foregroundColor(colors.secondaryText)
        .padding(.bottom, 16)
    }

    private func timeline(colors: CursorColors) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(commits.enumerated()), id: \.element.id) { index, commit in
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 0) {
                        Circle()
                            .fill(colors.mutedText.opacity(0.6))
                            .frame(width: 8, height: 8)
                            .padding(.top, 5)
                        if index < commits.count - 1 {
                            Rectangle()
                                .fill(colors.hairline)
                                .frame(width: 1)
                                .frame(maxHeight: .infinity)
                        }
                    }
                    .frame(width: 8)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top) {
                            Text(commit.title)
                                .font(CursorType.rowTitle)
                                .foregroundColor(colors.primaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            Text(commit.relativeTime)
                                .font(CursorType.rowSecondary)
                                .foregroundColor(colors.mutedText)
                        }
                        HStack(spacing: 6) {
                            ZStack {
                                Circle().fill(colors.iconButtonBackground)
                                Image(systemName: "cube.box.fill")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(colors.secondaryText)
                            }
                            .frame(width: 18, height: 18)
                            Text(commit.author)
                                .font(CursorType.rowSecondary)
                                .foregroundColor(colors.secondaryText)
                            Text("·")
                                .foregroundColor(colors.mutedText)
                            CursorDiffStatText(added: commit.added, removed: commit.removed, font: CursorType.rowSecondary)
                        }
                    }
                    .padding(.bottom, 22)
                }
            }
        }
        .padding(.horizontal, CursorMetrics.rowHorizontalPadding)
    }
}

/// "Copied Link" / "Copied ID" pill toast (IMG_2431): a small blurred capsule
/// centered at the top of the screen, auto-dismissed by the caller. Shared by
/// `CursorWorkThreadView` and `CursorPRDetailView` (same module — internal
/// visibility is enough, no DesignSystem export needed for two call sites).
struct CursorCopiedToast: View {
    @Environment(\.cursorScheme) private var cursorScheme

    let text: String

    var body: some View {
        let colors = CursorColors.resolve(cursorScheme)
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
            Text(text)
                .font(CursorType.statusPill)
        }
        .foregroundColor(colors.primaryText)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(colors.hairline, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
        .accessibilityIdentifier("copied-toast")
    }
}
#endif
