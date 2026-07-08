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
public struct CursorReviewDiffView: View {
    @Environment(\.cursorShellLiveBridge) private var liveBridge

    private enum Decision: Equatable {
        case pending
        case approved
        case denied
        case replied
    }

    @State private var decision: Decision = .pending

    private let onBack: () -> Void

    public init(onBack: @escaping () -> Void = {}) {
        self.onBack = onBack
    }

    private var approval: Approval? {
        guard let id = liveBridge?.pendingApprovalID else { return nil }
        // Prefer the Observable-tracked object (re-renders when set); the
        // lookup closure reads untracked AppRoot @State and is fallback only.
        if let resolved = liveBridge?.pendingApproval, resolved.id == id {
            return resolved
        }
        return liveBridge?.lookupApproval?(id)
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
        .background(CursorColors.light.background.ignoresSafeArea())
        .environment(\.cursorScheme, .light)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("review-diff-screen")
        .onAppear {
            Logger(subsystem: "dev.lancer.mobile", category: "CursorReviewDiffView")
                .info("review onAppear: bridge=\(liveBridge != nil, privacy: .public) pendingID=\(liveBridge?.pendingApprovalID?.uuidString ?? "nil", privacy: .public) bound=\(approval != nil, privacy: .public)")
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
                .foregroundColor(CursorColors.light.primaryText)
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
                    .foregroundColor(CursorColors.light.primaryText)
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
                    .foregroundColor(CursorColors.light.secondaryText)
                    .frame(width: 96, alignment: .leading)
                Text(value)
                    .font(CursorType.inlineCode)
                    .foregroundColor(CursorColors.light.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)

            if !isLast {
                Rectangle()
                    .fill(CursorColors.light.hairline)
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
                        .foregroundColor(CursorColors.light.primaryText)
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
                        .foregroundColor(CursorColors.light.mutedText)
                }
            }
        }
    }

    private var commandBlock: some View {
        Text(approval?.command ?? approval?.toolInput ?? approval?.patch ?? "(no command recorded)")
            .font(CursorType.diffCode)
            .foregroundColor(CursorColors.light.primaryText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(CursorColors.light.background)
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
                segments: [CursorPillButton.Segment("Deny", color: CursorColors.light.dangerRed)],
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
        case .approved: return CursorColors.light.successGreen
        case .denied: return CursorColors.light.dangerRed
        case .replied: return CursorColors.light.secondaryText
        case .pending: return CursorColors.light.primaryText
        }
    }

    // MARK: Audit

    private var auditLine: some View {
        Text(auditText)
            .font(CursorType.logLine)
            .foregroundColor(CursorColors.light.mutedText)
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
            .foregroundColor(CursorColors.light.secondaryText)
    }
}
#endif
