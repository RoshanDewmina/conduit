#if os(iOS)
import SwiftUI

/// Visual clone of Cursor's mobile Work Thread transcript: a user prompt bubble
/// followed by narration prose, a plan card, a to-dos card, and a changes card,
/// with a floating sticky action rail above a follow-up composer. Static seed
/// data only — no daemon/network wiring. Forces `.dark` regardless of the rest
/// of the app; Work Thread is Cursor's one dark screen.
public struct CursorWorkThreadView: View {
    @State private var isTodosExpanded = false
    @State private var isActionRailExpanded = true

    private let missionTitle: String
    private let onBack: () -> Void
    private let onViewPR: () -> Void
    private let onOpenReview: () -> Void
    private let onOpenComposer: () -> Void

    public init(
        missionTitle: String = "Fix onboarding pairing flow",
        onBack: @escaping () -> Void = {},
        onViewPR: @escaping () -> Void = {},
        onOpenReview: @escaping () -> Void = {},
        onOpenComposer: @escaping () -> Void = {}
    ) {
        self.missionTitle = missionTitle
        self.onBack = onBack
        self.onViewPR = onViewPR
        self.onOpenReview = onOpenReview
        self.onOpenComposer = onOpenComposer
    }

    public var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    userPromptBubble
                    narration
                    planCard
                    todosCard
                    changesCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 12)
            }
        }
        .background(CursorColors.dark.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                approvalBanner

                if isActionRailExpanded {
                    CursorActionRail(
                        buttons: [
                            CursorPillButton(
                                segments: [
                                    .init("View PR"),
                                    .init("+858", color: CursorColors.dark.successGreen),
                                    .init("-38", color: CursorColors.dark.dangerRed)
                                ],
                                style: .secondary,
                                action: onViewPR
                            ),
                            CursorPillButton(title: "Mark Ready", style: .secondary, action: {})
                        ],
                        onCollapse: { isActionRailExpanded = false }
                    )
                } else {
                    collapsedActionRailHandle
                }
                composer
            }
        }
        .environment(\.cursorScheme, .dark)
    }

    // MARK: Needs-approval banner

    /// Governed-approval interruption surfaced above the sticky action rail —
    /// Work Thread's own screenshots don't show this state, but the daemon's
    /// approval gate can trip mid-run, so the thread needs a way to demand
    /// attention without leaving the screen.
    private var approvalBanner: some View {
        Button(action: onOpenReview) {
            CursorArtifactCard {
                HStack(spacing: 10) {
                    CursorStatusBadge(kind: .risk(level: .high), label: "Needs your approval")
                    Text("Deploy to production")
                        .font(CursorType.bodyText)
                        .foregroundColor(CursorColors.dark.secondaryText)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(CursorColors.dark.secondaryText)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, CursorMetrics.actionRailHorizontalPadding)
        .padding(.top, CursorMetrics.actionRailVerticalPadding)
    }

    // MARK: Composer

    /// The whole composer area is tappable to open the fuller composer sheet,
    /// rather than editing inline — matches the Home/Workspaces composer-tap
    /// convention. The real `CursorBottomComposer` is rendered for visual
    /// fidelity but has hit-testing disabled so its `TextField` never steals
    /// first responder; an invisible button on top forwards the tap.
    private var composer: some View {
        ZStack {
            CursorBottomComposer(placeholder: "Follow up...")
                .allowsHitTesting(false)
            Button(action: onOpenComposer) {
                Color.clear
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Header

    private var header: some View {
        CursorHeaderBar(
            leading: AnyView(
                CursorIconButton(systemImageName: "chevron.left", action: onBack)
            ),
            trailing: [
                CursorIconButton(systemImageName: "ellipsis", action: {})
            ]
        )
        .overlay(alignment: .center) {
            HStack(spacing: 6) {
                Text(missionTitle)
                    .font(CursorType.sheetTitle)
                    .foregroundColor(CursorColors.dark.primaryText)
                    .lineLimit(1)
                Image(systemName: "display")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(CursorColors.dark.secondaryText)
            }
            .padding(.top, CursorMetrics.headerTopPadding)
        }
    }

    // MARK: User prompt bubble

    private var userPromptBubble: some View {
        HStack {
            Spacer(minLength: 48)
            Text("The pairing screen is stuck on \u{201c}Waiting for device\u{2026}\u{201d} after a fresh install. Figure out why and fix it end to end.")
                .font(CursorType.bodyText)
                .foregroundColor(CursorColors.dark.primaryText)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(CursorColors.dark.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 20))
        }
    }

    // MARK: Narration

    private var narration: some View {
        VStack(alignment: .leading, spacing: 14) {
            logLine("Worked 2m 41s")
            createdPlanLine
            logLine("Worked 34s")

            Text("No commit or push is needed from this session.")
                .font(CursorType.bodyText)
                .foregroundColor(CursorColors.dark.primaryText)

            whyParagraph

            Text("Root cause: the relay reconnect path never registered the device's push token after a cold launch, so the backend kept the pairing request pending. Files touched:")
                .font(CursorType.bodyText)
                .foregroundColor(CursorColors.dark.primaryText)

            VStack(alignment: .leading, spacing: 8) {
                bulletFilePath("Packages/LancerKit/Sources/AppFeature/PairingView.swift")
                bulletFilePath("Packages/LancerKit/Sources/RelayKit/E2ERelayClient.swift")
                bulletFilePath("daemon/lancerd/relay/register.go")
            }
        }
    }

    private var createdPlanLine: some View {
        HStack(spacing: 4) {
            Text("Created plan")
                .font(CursorType.logLine)
                .foregroundColor(CursorColors.dark.secondaryText)
            Text("Pairing Reconnect Fix")
                .font(CursorType.logLine)
                .foregroundColor(CursorColors.dark.statusDotActive)
        }
    }

    private var whyParagraph: some View {
        (
            Text("Why: ").font(CursorType.bodyEmphasis).foregroundColor(CursorColors.dark.primaryText)
            + Text("the pairing sheet polls the relay for a device-registered acknowledgment, but on a fresh install the app only registers its APNs token on cold launch, not on reconnect — so a second attempt after backgrounding never re-announces itself.")
                .font(CursorType.bodyText)
                .foregroundColor(CursorColors.dark.primaryText)
        )
    }

    private func logLine(_ text: String) -> some View {
        Text(text)
            .font(CursorType.logLine)
            .foregroundColor(CursorColors.dark.secondaryText)
    }

    private func bulletFilePath(_ path: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\u{2022}")
                .font(CursorType.bodyText)
                .foregroundColor(CursorColors.dark.secondaryText)
            inlineCodeChip(path)
        }
    }

    private func inlineCodeChip(_ text: String) -> some View {
        Text(text)
            .font(CursorType.inlineCode)
            .foregroundColor(CursorColors.dark.primaryText)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(CursorColors.dark.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: Plan card

    private var planCard: some View {
        CursorArtifactCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Pairing Reconnect Fix — 3 task briefs")
                    .font(CursorType.cardTitle)
                    .foregroundColor(CursorColors.dark.primaryText)

                Text("Register the device's push token on every relay reconnect, not just cold launch, and surface a clear timeout state on the pairing sheet if registration doesn't land within 15 seconds.")
                    .font(CursorType.bodyText)
                    .foregroundColor(CursorColors.dark.secondaryText)

                Text("Add a regression test that simulates a backgrounded-then-foregrounded app reconnecting to the relay, to catch this class of bug before it reaches TestFlight.")
                    .font(CursorType.bodyText)
                    .foregroundColor(CursorColors.dark.secondaryText)
            }
        }
    }

    // MARK: To-dos card

    private var todosCard: some View {
        CursorArtifactCard {
            VStack(alignment: .leading, spacing: 0) {
                Text("To-dos 5/8")
                    .font(CursorType.cardTitle)
                    .foregroundColor(CursorColors.dark.primaryText)
                    .padding(.bottom, 12)

                todoRow("Register APNs token on every relay reconnect, not just cold launch", done: true)
                todoRow("Add 15s registration timeout with a clear error state on the pairing sheet", done: true)
                todoRow("Fix deviceRegister relay message missing on backgrounded reconnect", done: true)
                todoRow("Add regression test for backgrounded-then-foregrounded reconnect", done: true)
                todoRow("Verify fix against the sandbox and prod APNs hosts", done: true)

                if isTodosExpanded {
                    todoRow("Update KNOWN_ISSUES.md to close out the pairing timeout entry", done: false)
                    todoRow("Confirm fix on a real device over cellular, not just Wi-Fi", done: false)
                    todoRow("Open PR against master with before/after pairing logs", done: false, isLast: true)
                } else {
                    expandRow
                }
            }
        }
    }

    private func todoRow(_ title: String, done: Bool, isLast: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 10) {
            CursorCheckDot(isChecked: done)
            Text(title)
                .font(CursorType.bodyText)
                .foregroundColor(done ? CursorColors.dark.mutedText : CursorColors.dark.primaryText)
                .strikethrough(done, color: CursorColors.dark.mutedText)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }

    private var expandRow: some View {
        Button(action: { isTodosExpanded = true }) {
            HStack(spacing: 10) {
                Text("\u{2022}\u{2022}\u{2022}")
                    .font(CursorType.bodyText)
                    .foregroundColor(CursorColors.dark.mutedText)
                    .frame(width: CursorMetrics.checkDotDiameter, alignment: .center)
                Text("3 more")
                    .font(CursorType.bodyText)
                    .foregroundColor(CursorColors.dark.secondaryText)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    // MARK: Changes card

    private var changesCard: some View {
        CursorArtifactCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text("Changes")
                        .font(CursorType.cardTitle)
                        .foregroundColor(CursorColors.dark.primaryText)
                    Text("3")
                        .font(CursorType.cardTitle)
                        .foregroundColor(CursorColors.dark.secondaryText)
                }
                .padding(.bottom, 10)

                changeRow("PairingView.swift", added: 47, removed: 6)
                changeRow("E2ERelayClient.swift", added: 62, removed: 11)
                changeRow("relay/register.go", added: 34, removed: 2, isLast: true)
            }
        }
    }

    private func changeRow(_ filename: String, added: Int, removed: Int, isLast: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "doc")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(CursorColors.dark.secondaryText)
                Text(filename)
                    .font(CursorType.bodyText)
                    .foregroundColor(CursorColors.dark.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 8)
                CursorDiffStatText(added: added, removed: removed, font: CursorType.statusPill)
            }
            .padding(.vertical, 10)

            if !isLast {
                Rectangle()
                    .fill(CursorColors.dark.hairline)
                    .frame(height: CursorMetrics.cardHairlineHeight)
            }
        }
    }

    // MARK: Collapsed action rail handle

    private var collapsedActionRailHandle: some View {
        HStack {
            Spacer()
            CursorIconButton(
                systemImageName: "chevron.up",
                diameter: CursorMetrics.pillButtonHeight,
                action: { isActionRailExpanded = true }
            )
            .padding(.trailing, CursorMetrics.actionRailHorizontalPadding)
            .padding(.top, CursorMetrics.actionRailVerticalPadding)
        }
    }
}
#endif
