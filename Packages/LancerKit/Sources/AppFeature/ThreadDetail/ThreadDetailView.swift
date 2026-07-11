#if os(iOS)
import SwiftUI

/// Section 7 of the frontend rebuild: a faithful, Apple-native recreation of
/// the Cursor-mobile thread detail screen (owner reference screenshots
/// `docs/design/cursor-reference/IMG_2354` / `IMG_2358`–`2360`). Pushed via
/// `NavigationLink` when tapping a thread row in `ThreadListView` (Section 5)
/// or `WorkspacesView`'s DEBUG seam.
/// Visual-only for this milestone — the user message, assistant response,
/// table, and changed files are entirely invented static content, not real
/// `SessionFeature`/chat-engine output. The "..." menu, the "Changes" file
/// row, and "Mark Ready" are decorative (no gesture handler, matching
/// the "line.3.horizontal" precedent in `ThreadListView`). "View PR" is the
/// one functional push, to `PRDetailView`. System `SF Symbols` + semantic
/// colors only, no DesignSystem module.
struct ThreadDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isFollowUpPresented = false

    let thread: ThreadRow

    init(thread: ThreadRow) {
        self.thread = thread
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ChatUserBubble(text: Self.userPrompt)
                            .padding(.top, 16)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Worked 26s")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)

                            ChatMarkdownBody(markdown: Self.assistantMarkdown)
                        }

                        summaryTable

                        ChatMarkdownBody(markdown: Self.wireframesMarkdown)

                        ChatChangesCard(files: Self.changedFiles)

                        pillRow
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 96)
                }
            }

            Button {
                isFollowUpPresented = true
            } label: {
                ChatFollowUpPlaceholderBar()
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isFollowUpPresented) {
            NewChatComposerView()
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                circleButton(systemImage: "chevron.left")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Back"))

            Spacer()

            HStack(spacing: 6) {
                Text(thread.title)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)

            Spacer()

            circleButton(systemImage: "ellipsis")
                .accessibilityHidden(true)
        }
    }

    private func circleButton(systemImage: String) -> some View {
        Circle()
            .fill(Color(.secondarySystemBackground))
            .frame(width: 40, height: 40)
            .overlay(
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
            )
    }

    // MARK: - Summary table

    private var summaryTable: some View {
        VStack(spacing: 0) {
            ForEach(Array(Self.summaryRows.enumerated()), id: \.offset) { index, row in
                HStack(alignment: .top, spacing: 0) {
                    Text(row.label)
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 96, alignment: .leading)
                        .padding(.vertical, 12)
                        .padding(.leading, 14)

                    Divider()

                    Text(row.value)
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                        .padding(.trailing, 14)
                        .padding(.leading, 12)
                }

                if index < Self.summaryRows.count - 1 {
                    Divider()
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(.separator), lineWidth: 0.5)
        )
    }

    // MARK: - Pills

    private var pillRow: some View {
        HStack(spacing: 10) {
            NavigationLink {
                PRDetailView()
            } label: {
                ChatOutlinePillLabel(
                    title: "View PR",
                    added: Self.prAdded,
                    removed: Self.prRemoved,
                    systemImage: "arrow.trianglehead.branch"
                )
            }
            .buttonStyle(.plain)

            ChatOutlinePillLabel(title: "Mark Ready")
        }
        .padding(.top, 4)
    }

    // MARK: - Static sample data

    private struct SummaryRow {
        let label: String
        let value: String
    }

    private static let userPrompt =
        "Can you take a look at the onboarding flow and clean up the handoff between the permissions screen and account setup? It feels like there are a couple of redundant taps in there."

    private static let assistantMarkdown = """
    I went through the onboarding flow and found a few places where **step ordering** was causing the redundant taps you mentioned. The permissions screen was requesting camera access before it was actually needed, which pushed users through an extra confirmation step later on.

    The fix consolidates permission requests into a single `PermissionCoordinator` pass and removes the duplicate account-setup confirmation screen. I also tightened up the transition animation so the flow feels like one continuous handoff instead of five separate screens.
    """

    private static let wireframesMarkdown =
        "**Screens touched:** Welcome, Permissions, Account setup, Tutorial, Confirmation."

    private static let summaryRows: [SummaryRow] = [
        SummaryRow(label: "Priority", value: "High"),
        SummaryRow(label: "Owner", value: "You"),
        SummaryRow(label: "Reviewers", value: "2 requested"),
        SummaryRow(label: "Target", value: "This sprint"),
        SummaryRow(label: "Risk", value: "Low"),
    ]

    private static let changedFiles: [ChangedFile] = [
        ChangedFile(badge: "SW", name: "OnboardingCoordinator.swift", added: 96, removed: 18),
        ChangedFile(badge: "SW", name: "PermissionRequestView.swift", added: 46, removed: 0),
    ]

    private static let prAdded = 142
    private static let prRemoved = 18
}

// MARK: - Shared helpers (used by ThreadDetailView + PRDetailView)

func fileBadge(_ text: String) -> some View {
    RoundedRectangle(cornerRadius: 6, style: .continuous)
        .fill(Color(.tertiarySystemFill))
        .frame(width: 28, height: 20)
        .overlay(
            Text(text)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
        )
}

/// Built from an `AttributedString` so the added/removed counts keep
/// distinct colors without the deprecated `Text` `+` concatenation operator.
func diffStatText(added: Int, removed: Int) -> Text {
    chatDiffStatText(added: added, removed: removed)
}

#Preview {
    NavigationStack {
        ThreadDetailView(thread: ThreadRow(title: "Fix onboarding flow", status: .checksPassed, diffStat: "+142 -18"))
    }
}
#endif
