#if os(iOS)
import SwiftUI
import DesignSystem
import LancerCore

/// Visual clone of a Cursor-style "Approval Review" screen: a single reusable
/// anatomy (request, scope, risk, evidence, decision, audit) for a governed
/// approval. Static seed data only — no daemon/network wiring; decision
/// buttons flip a local `@State` to show a confirmation state rather than
/// sending anything.
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

    private var requestCard: some View {
        CursorArtifactCard {
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("Request")
                Text("Run terraform apply on the push-backend production workspace")
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

                scopeRow("Machine", "mac-mini-studio")
                scopeRow("Repo", "push-backend")
                scopeRow("Branch", "master")
                scopeRow("Files", "infra/production.tfvars")
                scopeRow("Command", "terraform apply -var-file=infra/production.tfvars")
                scopeRow("Environment", "production", isLast: true)
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

    private var riskCard: some View {
        CursorArtifactCard {
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("Risk")

                CursorStatusBadge(kind: .risk(level: .high), label: "High risk")

                Text("This applies infrastructure changes directly to the production workspace.")
                    .font(CursorType.bodyText)
                    .foregroundColor(CursorColors.light.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Terraform can recreate or destroy live cloud resources; there is no rollback once the apply starts.")
                    .font(CursorType.bodyText)
                    .foregroundColor(CursorColors.light.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Evidence

    private var evidenceCard: some View {
        CursorArtifactCard {
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel("Evidence")

                commandBlock

                HStack(spacing: 8) {
                    Text("Changes")
                        .font(CursorType.bodyEmphasis)
                        .foregroundColor(CursorColors.light.primaryText)
                    CursorDiffStatText(added: 12, removed: 3, font: CursorType.statusPill)
                }

                VStack(spacing: 0) {
                    changedFileRow("infra/production.tfvars", added: 9, removed: 2)
                    changedFileRow("modules/vpc/main.tf", added: 3, removed: 1, isLast: true)
                }

                viewFullDiffRow
            }
        }
    }

    private var commandBlock: some View {
        Text("terraform apply -var-file=infra/production.tfvars")
            .font(CursorType.diffCode)
            .foregroundColor(CursorColors.light.primaryText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(CursorColors.light.background)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func changedFileRow(_ filename: String, added: Int, removed: Int, isLast: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "doc")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(CursorColors.light.secondaryText)
                Text(filename)
                    .font(CursorType.bodyText)
                    .foregroundColor(CursorColors.light.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                CursorDiffStatText(added: added, removed: removed, font: CursorType.statusPill)
            }
            .padding(.vertical, 8)

            if !isLast {
                Rectangle()
                    .fill(CursorColors.light.hairline)
                    .frame(height: CursorMetrics.cardHairlineHeight)
            }
        }
    }

    private var viewFullDiffRow: some View {
        Button(action: {}) {
            HStack(spacing: 8) {
                Text("View full diff")
                    .font(CursorType.bodyText)
                    .foregroundColor(CursorColors.light.statusDotActive)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(CursorColors.light.mutedText)
            }
            .padding(.top, 4)
        }
        .buttonStyle(.plain)
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
        decision = local
        guard let relay, let liveBridge, let approvalID = liveBridge.pendingApprovalID else { return }
        Task { await liveBridge.onDecide?(approvalID, relay) }
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
