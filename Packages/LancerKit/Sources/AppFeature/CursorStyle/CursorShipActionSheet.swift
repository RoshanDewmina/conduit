#if os(iOS)
import SwiftUI
import DesignSystem

/// Confirmation sheet for a phone-initiated git/PR "ship action" (branch,
/// stage+commit, open a PR) — the phone-side counterpart to
/// `daemon/lancerd/shipactions.go`. This is a small, self-contained,
/// presentational component: it takes a fully-formed `Draft` and `Readiness`
/// snapshot and reports the user's decision via `onConfirm`/`onCancel`. It
/// does not call the daemon itself and is not wired into live navigation —
/// the real Git/PR data source is out of scope repo-wide right now (see
/// `CursorPRDetailView`, which stays untouched and unwired by this file).
///
/// Tapping "Stage for Approval" does not ship anything by itself: per the
/// daemon-side contract, this only *proposes* the action (`agent.ship.propose`)
/// and the same explicit phone approval flow used for every other high-risk
/// action must still confirm it before `lancerd` executes a single git/gh
/// command. There is no merge control here, or anywhere in this component —
/// merge-from-phone is a permanent, separate, not-yet-designed gate (see
/// docs/plans/2026-07-08-lancer-layer-4-6-lane-proposal.md, "Owner decisions" §3).
public struct CursorShipActionSheet: View {
    /// The staged branch/commit/PR request this sheet is confirming. Mirrors
    /// `shipActionParams` on the daemon side field-for-field so a future
    /// wiring pass can serialize this directly into the RPC call.
    public struct Draft: Sendable {
        public let branch: String?
        public let baseBranch: String?
        public let commitMessage: String
        public let openPR: Bool
        public let prTitle: String?
        public let prBase: String?

        public init(
            branch: String? = nil,
            baseBranch: String? = nil,
            commitMessage: String,
            openPR: Bool = false,
            prTitle: String? = nil,
            prBase: String? = nil
        ) {
            self.branch = branch
            self.baseBranch = baseBranch
            self.commitMessage = commitMessage
            self.openPR = openPR
            self.prTitle = prTitle
            self.prBase = prBase
        }
    }

    /// Mirrors `shipPreflightResult` on the daemon side — host readiness,
    /// surfaced before the action is offered so a phone-initiated ship action
    /// doesn't fail destructively mid-execution on an unprepared host.
    public struct Readiness: Sendable {
        public let ready: Bool
        public let ghAuthenticated: Bool
        public let remoteReachable: Bool
        public let hasConflicts: Bool
        public let reasons: [String]

        public init(
            ready: Bool,
            ghAuthenticated: Bool = true,
            remoteReachable: Bool = true,
            hasConflicts: Bool = false,
            reasons: [String] = []
        ) {
            self.ready = ready
            self.ghAuthenticated = ghAuthenticated
            self.remoteReachable = remoteReachable
            self.hasConflicts = hasConflicts
            self.reasons = reasons
        }
    }

    @Environment(\.cursorScheme) private var cursorScheme

    private let draft: Draft
    private let readiness: Readiness
    private let onCancel: () -> Void
    private let onConfirm: () -> Void

    public init(
        draft: Draft,
        readiness: Readiness,
        onCancel: @escaping () -> Void = {},
        onConfirm: @escaping () -> Void = {}
    ) {
        self.draft = draft
        self.readiness = readiness
        self.onCancel = onCancel
        self.onConfirm = onConfirm
    }

    public var body: some View {
        CursorBottomSheetContainer(
            title: "Ship Changes",
            leadingButton: (systemImageName: "xmark", action: onCancel)
        ) {
            VStack(alignment: .leading, spacing: 0) {
                riskBadge
                summaryRows
                readinessSection
                scopeNote
                confirmButton
            }
            .padding(.bottom, CursorMetrics.sheetContentBottomPadding)
        }
    }

    // MARK: Risk badge

    private var riskBadge: some View {
        let colors = CursorColors.resolve(cursorScheme)
        return HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
            Text("HIGH RISK — requires explicit approval")
                .font(CursorType.statusPill)
        }
        .foregroundColor(colors.riskHigh)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(colors.riskHigh.opacity(0.12))
        .clipShape(Capsule())
        .padding(.horizontal, CursorMetrics.rowHorizontalPadding)
        .padding(.top, 4)
        .accessibilityIdentifier("ship-action-risk-badge")
    }

    // MARK: Summary rows

    @ViewBuilder
    private var summaryRows: some View {
        VStack(spacing: 0) {
            if let branch = draft.branch {
                infoRow(icon: "arrow.triangle.branch", title: "New branch", value: branch)
            }
            infoRow(icon: "text.quote", title: "Commit message", value: draft.commitMessage)
            if draft.openPR {
                infoRow(icon: "arrow.up.right.square", title: "Pull request", value: draft.prTitle ?? "Open PR")
            }
        }
        .padding(.top, 8)
    }

    private func infoRow(icon: String, title: String, value: String) -> some View {
        let colors = CursorColors.resolve(cursorScheme)
        return VStack(spacing: 0) {
            HStack(alignment: .top, spacing: CursorMetrics.rowSpacing) {
                Image(systemName: icon)
                    .font(.system(size: CursorMetrics.rowIconSize - 6, weight: .regular))
                    .foregroundColor(colors.secondaryText)
                    .frame(width: CursorMetrics.rowIconSize, height: CursorMetrics.rowIconSize)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(CursorType.rowSecondary)
                        .foregroundColor(colors.secondaryText)
                    Text(value)
                        .font(CursorType.rowTitle)
                        .foregroundColor(colors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, CursorMetrics.rowHorizontalPadding)
            .padding(.vertical, CursorMetrics.rowVerticalPadding)
            Rectangle()
                .fill(colors.hairline)
                .frame(height: CursorMetrics.rowHairlineHeight)
                .padding(.leading, CursorMetrics.rowHairlineLeadingInsetWithIcon)
        }
    }

    // MARK: Readiness

    private var readinessSection: some View {
        let colors = CursorColors.resolve(cursorScheme)
        return VStack(alignment: .leading, spacing: 6) {
            CursorSectionHeader("Host readiness")
            if readiness.reasons.isEmpty {
                readinessLine(ok: true, text: "Host is ready to ship")
            } else {
                ForEach(Array(readiness.reasons.enumerated()), id: \.offset) { _, reason in
                    readinessLine(ok: false, text: reason)
                }
            }
        }
        .padding(.horizontal, CursorMetrics.rowHorizontalPadding)
        .padding(.top, 4)
        .foregroundColor(colors.secondaryText)
    }

    private func readinessLine(ok: Bool, text: String) -> some View {
        let colors = CursorColors.resolve(cursorScheme)
        return HStack(alignment: .top, spacing: 6) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(ok ? colors.riskLow : colors.riskCritical)
            Text(text)
                .font(CursorType.rowSecondary)
                .foregroundColor(colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Scope note

    private var scopeNote: some View {
        let colors = CursorColors.resolve(cursorScheme)
        return Text("Ship actions stop at opening a pull request. Merging is not available from the phone.")
            .font(CursorType.rowSecondary)
            .foregroundColor(colors.mutedText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, CursorMetrics.rowHorizontalPadding)
            .padding(.top, 12)
            .accessibilityIdentifier("ship-action-no-merge-note")
    }

    // MARK: Confirm button

    private var confirmButton: some View {
        let colors = CursorColors.resolve(cursorScheme)
        return Button {
            Haptics.medium()
            onConfirm()
        } label: {
            Text("Stage for Approval")
                .font(CursorType.rowTitle)
                .foregroundColor(colors.pillPrimaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(readiness.ready ? colors.pillPrimaryBackground : colors.mutedText.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: CursorMetrics.composerCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!readiness.ready)
        .padding(.horizontal, CursorMetrics.rowHorizontalPadding)
        .padding(.top, 16)
        .accessibilityIdentifier("ship-action-confirm-button")
    }
}
#endif
