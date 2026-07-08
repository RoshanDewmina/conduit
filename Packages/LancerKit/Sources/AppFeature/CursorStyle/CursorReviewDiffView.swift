#if os(iOS)
import SwiftUI
import DesignSystem
import LancerCore
import os

/// A governed-approval review screen: request, scope, risk, evidence,
/// decision, audit — bound to the REAL pending `Approval` behind
/// `liveBridge.pendingApprovalID` via `liveBridge.lookupApproval`. Previously
/// every field here (command, risk, scope, changed files) was hardcoded to
/// one fake "terraform apply" example regardless of what was actually
/// pending — a live test on 2026-07-07 showed a real fileWrite request
/// rendered as that fake example, meaning the user had no way to see what
/// they were actually approving.
///
/// ## The A3-R4 binding regression (screen-map evidence 12.05.34) and its fix
///
/// Once a decision is made, `AppRoot`'s `onPendingApprovalsChanged(count: 0, ...)`
/// handler clears `liveBridge.pendingApprovalID`/`pendingApproval` back to `nil`
/// (see AppRoot.swift, the `onPendingApprovalsChanged` closure) — by design,
/// the approval is no longer "pending" once decided. But this view's `decision`
/// local `@State` only ever moves forward (pending → approved/denied/replied)
/// and never resets, so a second render after the clear showed a real, live
/// contradiction: the Request/Scope/Risk/Evidence cards (which read `approval`
/// directly, now nil) fell back to "No pending approval" / "—" placeholders,
/// while the Decision card and audit line (driven by the frozen `decision`
/// @State) kept showing "Approved · Decided by You". Root cause: the display
/// fields and the decision-result fields were reading two different sources of
/// truth — one live (and nil'd on completion), one a local snapshot (never
/// nil'd) — with nothing keeping them in sync.
///
/// The fix: `boundApproval` snapshots the live `Approval` the moment it's
/// non-nil (on appear and whenever `pendingApprovalID` changes) and freezes it
/// once the ID is cleared post-decision, so Request/Scope/Risk/Evidence keep
/// showing the SAME approval the Decision card/audit line describe. When a
/// genuinely new approval arrives (a different id), the snapshot — and the
/// local `decision` state — reset. This is a display-binding fix only; the
/// actual approve/deny/reply relay call in `applyDecision` is unchanged.
public struct CursorReviewDiffView: View {
    @Environment(\.cursorShellLiveBridge) private var liveBridge
    @Environment(\.cursorScheme) private var cursorScheme

    private enum Decision: Equatable {
        case pending
        case approved
        case denied
        case replied
    }

    @State private var decision: Decision = .pending
    /// Frozen snapshot of the bound approval — see the type-level doc comment
    /// above for why this exists. Never cleared back to `nil` by a live signal;
    /// only replaced when a genuinely new approval id is bound.
    @State private var boundApproval: Approval?

    private let onBack: () -> Void

    public init(onBack: @escaping () -> Void = {}) {
        self.onBack = onBack
    }

    private var colors: CursorColors { CursorColors.resolve(cursorScheme) }

    /// The live approval straight from the bridge — goes `nil` once AppRoot
    /// clears `pendingApprovalID` after a decision is relayed. Use `approval`
    /// (below) for display; this is only the raw signal used to refresh the
    /// snapshot.
    private var liveApproval: Approval? {
        guard let id = liveBridge?.pendingApprovalID else { return nil }
        // Prefer the Observable-tracked object (re-renders when set); the
        // lookup closure reads untracked AppRoot @State and is fallback only.
        if let resolved = liveBridge?.pendingApproval, resolved.id == id {
            return resolved
        }
        return liveBridge?.lookupApproval?(id)
    }

    /// What every display card should render: the frozen snapshot once bound,
    /// falling back to the live value before the first bind completes.
    private var approval: Approval? { boundApproval ?? liveApproval }

    /// Seeds/refreshes `boundApproval` from the live bridge. Safe to call from
    /// both `onAppear` (first render may already have a non-nil id) and
    /// `onChange(of: liveBridge?.pendingApprovalID)` (id changes after appear).
    /// Never writes `nil` — once a decision clears the live id, the snapshot
    /// stays frozen so display fields don't blank out from under the decision
    /// footer. A genuinely new id resets both the snapshot and local decision.
    private func syncBoundApproval() {
        guard let live = liveApproval else { return }
        if live.id != boundApproval?.id {
            decision = .pending
        }
        boundApproval = live
    }

    public var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    requestCard
                    scopeCard
                    riskCard
                    evidenceCard
                    decisionCard
                    if decision != .pending {
                        auditLine
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 24)
            }
        }
        .background(colors.background.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("review-diff-screen")
        .onAppear {
            syncBoundApproval()
            Logger(subsystem: "dev.lancer.mobile", category: "CursorReviewDiffView")
                .info("review onAppear: bridge=\(liveBridge != nil, privacy: .public) pendingID=\(liveBridge?.pendingApprovalID?.uuidString ?? "nil", privacy: .public) bound=\(approval != nil, privacy: .public)")
        }
        .onChange(of: liveBridge?.pendingApprovalID) { _, _ in
            syncBoundApproval()
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
            Text("Review")
                .font(CursorType.sheetTitle)
                .foregroundColor(colors.primaryText)
                .padding(.top, CursorMetrics.headerTopPadding)
        }
    }

    // MARK: Request

    private var requestTitle: String {
        guard let approval else { return "No pending approval" }
        if approval.kind == .askQuestion, let question = approval.question, !question.isEmpty {
            return question
        }
        return approval.command ?? approval.patch ?? "\(approval.kind.rawValue) request"
    }

    private var requestCard: some View {
        CursorArtifactCard {
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("Request")
                Text(requestTitle)
                    .font(CursorType.bodyEmphasis)
                    .foregroundColor(colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Scope

    private var scopeCard: some View {
        CursorArtifactCard {
            VStack(alignment: .leading, spacing: 0) {
                sectionLabel("Scope")
                    .padding(.bottom, 10)

                let a = approval
                scopeRow("Agent", a?.agent.rawValue ?? "—")
                scopeRow("Kind", a?.kind.rawValue ?? "—")
                scopeRow("Directory", a?.cwd.isEmpty == false ? a!.cwd : "—")
                if let toolName = a?.toolName, !toolName.isEmpty {
                    scopeRow("Tool", toolName)
                }
                scopeRow("Command", a?.command ?? "—", isLast: true)
            }
        }
    }

    private func scopeRow(_ label: String, _ value: String, isLast: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Text(label)
                    .font(CursorType.rowSecondary)
                    .foregroundColor(colors.secondaryText)
                    .frame(width: 96, alignment: .leading)
                Text(value)
                    .font(CursorType.inlineCode)
                    .foregroundColor(colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)

            if !isLast {
                Rectangle()
                    .fill(colors.hairline)
                    .frame(height: CursorMetrics.cardHairlineHeight)
            }
        }
    }

    // MARK: Risk

    private var riskLevel: CursorStatusBadge.RiskLevel {
        switch approval?.risk {
        case .critical: return .critical
        case .high: return .high
        case .medium: return .medium
        case .low, .none: return .low
        }
    }

    private var riskLabel: String {
        switch approval?.risk {
        case .critical: return "Critical risk"
        case .high: return "High risk"
        case .medium: return "Medium risk"
        case .low, .none: return "Low risk"
        }
    }

    private var riskCard: some View {
        CursorArtifactCard {
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("Risk")

                CursorStatusBadge(kind: .risk(level: riskLevel), label: riskLabel)

                if let blastRadius = approval?.blastRadius, let summary = blastRadiusSummary(blastRadius) {
                    Text(summary)
                        .font(CursorType.bodyText)
                        .foregroundColor(colors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Evidence

    private var evidenceCard: some View {
        CursorArtifactCard {
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel("Evidence")
                commandBlock
                if let hash = approval?.contentHash, !hash.isEmpty {
                    Text("content hash \(hash.prefix(12))…")
                        .font(CursorType.logLine)
                        .foregroundColor(colors.mutedText)
                }
            }
        }
    }

    private var commandBlock: some View {
        Text(approval?.command ?? approval?.toolInput ?? approval?.patch ?? "(no command recorded)")
            .font(CursorType.diffCode)
            .foregroundColor(colors.primaryText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(colors.background)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func blastRadiusSummary(_ blastRadius: ApprovalBlastRadius) -> String? {
        var parts: [String] = []
        if let files = blastRadius.files, !files.isEmpty {
            parts.append("Touches \(files.count) file\(files.count == 1 ? "" : "s")")
        }
        if blastRadius.touchesGit == true { parts.append("touches git") }
        if blastRadius.touchesNetwork == true { parts.append("touches network") }
        if let rule = blastRadius.matchedRule, !rule.isEmpty { parts.append("matched rule \(rule)") }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " \u{00b7} ")
    }

    // MARK: Decision

    private var decisionCard: some View {
        CursorArtifactCard {
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel("Decision")

                if decision == .pending {
                    decisionButtons
                } else {
                    decisionStatusLine
                }
            }
        }
    }

    private var decisionButtons: some View {
        HStack(spacing: CursorMetrics.pillButtonSpacing) {
            CursorPillButton(title: "Approve", style: .primary) {
                applyDecision(.approved, relay: .approved)
            }
            .accessibilityIdentifier("cursor.review.approve")
            CursorPillButton(
                segments: [CursorPillButton.Segment("Deny", color: colors.dangerRed)],
                style: .secondary
            ) {
                applyDecision(.denied, relay: .rejected)
            }
            CursorPillButton(title: "Reply", style: .secondary) {
                applyDecision(.replied, relay: nil)
            }
        }
    }

    private func applyDecision(_ local: Decision, relay: Approval.Decision?) {
        guard let relay, let liveBridge, let approvalID = liveBridge.pendingApprovalID else {
            decision = local
            return
        }
        Task {
            await liveBridge.onDecide?(approvalID, relay)
            decision = local
        }
    }

    private var decisionStatusLine: some View {
        HStack(spacing: 8) {
            Image(systemName: decisionIconName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(decisionColor)
            Text(decisionLabel)
                .font(CursorType.bodyEmphasis)
                .foregroundColor(decisionColor)
        }
    }

    private var decisionIconName: String {
        switch decision {
        case .approved: return "checkmark.circle.fill"
        case .denied: return "xmark.circle.fill"
        case .replied: return "arrowshape.turn.up.left.fill"
        case .pending: return ""
        }
    }

    private var decisionLabel: String {
        switch decision {
        case .approved: return "Approved"
        case .denied: return "Denied"
        case .replied: return "Reply sent"
        case .pending: return ""
        }
    }

    private var decisionColor: Color {
        switch decision {
        case .approved: return colors.successGreen
        case .denied: return colors.dangerRed
        case .replied: return colors.secondaryText
        case .pending: return colors.primaryText
        }
    }

    // MARK: Audit

    private var auditLine: some View {
        Text(auditText)
            .font(CursorType.logLine)
            .foregroundColor(colors.mutedText)
            .padding(.horizontal, 4)
    }

    private var auditText: String {
        switch decision {
        case .approved, .denied: return "Decided by You \u{00b7} just now"
        case .replied: return "Replied by You \u{00b7} just now"
        case .pending: return ""
        }
    }

    // MARK: Shared

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(CursorType.cardTitle)
            .foregroundColor(colors.secondaryText)
    }
}
#endif
