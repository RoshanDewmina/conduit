#if os(iOS)
import SwiftUI
import LancerCore

// MARK: - InboxApprovalDetail
//
// Drill-in view for a single approval. Shows full metadata, command block,
// and complete decision flow (Deny / Edit & run / Allow always / Approve).

public struct InboxApprovalDetail: View {
    let agentKey: AgentKey
    let agentName: String
    let hostLabel: String
    let cwd: String
    let sessionID: String?
    let timeLabel: String
    let summary: String?
    let question: String?
    let choices: [String]?
    let toolName: String?
    let args: String?
    let command: String?
    let risk: Int
    let matchedRule: String?
    /// Non-nil when the approval is already resolved — show read-only history mode.
    let resolvedDecision: Approval.Decision?
    let onDeny: (() -> Void)?
    let onEditAndRun: (() -> Void)?
    let onAllowAlways: (() -> Void)?
    let onApprove: (() -> Void)?
    let onChoose: ((Int) -> Void)?

    @Environment(\.lancerTokens) private var t
    @State private var showDetails = false
    @State private var evidenceConfirmed = false

    public init(
        agentKey: AgentKey,
        agentName: String,
        hostLabel: String,
        cwd: String,
        sessionID: String? = nil,
        timeLabel: String,
        summary: String? = nil,
        question: String? = nil,
        choices: [String]? = nil,
        toolName: String? = nil,
        args: String? = nil,
        command: String? = nil,
        risk: Int,
        matchedRule: String? = nil,
        resolvedDecision: Approval.Decision? = nil,
        onDeny: (() -> Void)? = nil,
        onEditAndRun: (() -> Void)? = nil,
        onAllowAlways: (() -> Void)? = nil,
        onApprove: (() -> Void)? = nil,
        onChoose: ((Int) -> Void)? = nil
    ) {
        self.agentKey = agentKey
        self.agentName = agentName
        self.hostLabel = hostLabel
        self.cwd = cwd
        self.sessionID = sessionID
        self.timeLabel = timeLabel
        self.summary = summary
        self.question = question
        self.choices = choices
        self.toolName = toolName
        self.args = args
        self.command = command
        self.risk = risk
        self.matchedRule = matchedRule
        self.resolvedDecision = resolvedDecision
        self.onDeny = onDeny
        self.onEditAndRun = onEditAndRun
        self.onAllowAlways = onAllowAlways
        self.onApprove = onApprove
        self.onChoose = onChoose
    }

    public var body: some View {
        if let resolved = resolvedDecision {
            resolvedView(decision: resolved)
        } else {
            pendingView
        }
    }

    // MARK: - Read-only resolved view

    private func resolvedView(decision: Approval.Decision) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 6) {
                    AgentIdentityBadge(agent: agentKey, label: agentName)
                    Spacer()
                    Text(timeLabel)
                        .font(.dsMonoPt(11))
                        .foregroundStyle(t.text3)
                }

                HStack(spacing: 10) {
                    Image(systemName: decisionIcon(decision))
                        .font(.system(size: 20))
                        .foregroundStyle(decisionColor(decision))
                    Text(decisionLabel(decision))
                        .font(.dsSansPt(16, weight: .semibold))
                        .foregroundStyle(decisionColor(decision))
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(decisionColor(decision).opacity(0.08), in: RoundedRectangle(cornerRadius: t.r3, style: .continuous))

                if let summary, !summary.isEmpty {
                    Text(summary)
                        .font(.dsSansPt(14))
                        .foregroundStyle(t.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
        }
        .background(t.bg)
    }

    private func decisionLabel(_ d: Approval.Decision) -> String {
        switch d {
        case .approved:      "Approved ✓"
        case .approvedAlways: "Auto-approved ✓"
        case .rejected:      "Denied"
        case .expired:       "Approval expired — not actioned"
        }
    }

    private func decisionIcon(_ d: Approval.Decision) -> String {
        switch d {
        case .approved, .approvedAlways: "checkmark.circle.fill"
        case .rejected:                   "xmark.circle.fill"
        case .expired:                    "clock.badge.xmark"
        }
    }

    private func decisionColor(_ d: Approval.Decision) -> Color {
        switch d {
        case .approved, .approvedAlways: t.ok
        case .rejected:                   t.danger
        case .expired:                    t.text3
        }
    }

    // MARK: - Pending view

    private var pendingView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    pendingContent
                }
                .padding(16)
            }
            if !hasChoiceQuestion {
                decisionBar
            }
        }
        .background(t.bg)
    }

    @ViewBuilder
    private var pendingContent: some View {
        reviewHeader
        requestSection
        scopeSection

        if question != nil {
            if let choices, !choices.isEmpty {
                ReviewSection(title: "Choose a reply") {
                    ForEach(Array(choices.enumerated()), id: \.offset) { idx, label in
                        DSButton(label, variant: .quiet, size: .md, mono: true, fullWidth: true) {
                            onChoose?(idx)
                        }
                    }
                }
            }
        } else if let toolName {
            evidenceSection(toolName: toolName)
            if requiresEvidenceConfirmation {
                evidenceCheckToggle
            }
        }

        if hasExtraDetails {
            DisclosureGroup(isExpanded: $showDetails) {
                VStack(alignment: .leading, spacing: 0) {
                    if hostLabel != displayCwd {
                        metadataRow("Host", hostLabel)
                        Divider().overlay(t.border)
                    }
                    if let matchedRule, !matchedRule.isEmpty {
                        metadataRow("Policy rule", matchedRule)
                        if sessionID != nil { Divider().overlay(t.border) }
                    }
                    if let sessionID {
                        metadataRow("Session", sessionID)
                    }
                }
                .padding(.top, 8)
            } label: {
                Text("Details")
                    .font(.dsSansPt(13, weight: .medium))
                    .foregroundStyle(t.text3)
            }
            .tint(t.text3)
        }
    }

    private var reviewHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                AgentIdentityBadge(agent: agentKey, label: agentName)
                RiskBadge(risk: risk)
                Spacer()
                Text(timeLabel)
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)
            }

            Text(summaryText)
                .font(.dsSansPt(20, weight: .semibold))
                .foregroundStyle(t.text)
                .fixedSize(horizontal: false, vertical: true)

            Text(riskNarrative)
                .font(.dsSansPt(13))
                .foregroundStyle(t.text2)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.surface, in: RoundedRectangle(cornerRadius: t.r3, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: t.r3, style: .continuous).strokeBorder(t.border, lineWidth: 1))
    }

    @ViewBuilder
    private var requestSection: some View {
        if let question {
            ReviewSection(title: "Request") {
                Text(question)
                    .font(.dsSansPt(14))
                    .foregroundStyle(t.text)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        } else if let toolName {
            ReviewSection(title: "Request") {
                Text("Allow \(agentName) to use \(toolName).")
                    .font(.dsSansPt(14, weight: .medium))
                    .foregroundStyle(t.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var scopeSection: some View {
        ReviewSection(title: "Scope") {
            VStack(spacing: 0) {
                metadataRow("Agent", agentName)
                Divider().overlay(t.border)
                metadataRow("Project", displayCwd)
                if let sessionID {
                    Divider().overlay(t.border)
                    metadataRow("Session", sessionID)
                }
                if let matchedRule, !matchedRule.isEmpty {
                    Divider().overlay(t.border)
                    metadataRow("Policy", matchedRule)
                }
            }
            .background(t.surfaceSunk, in: RoundedRectangle(cornerRadius: t.r3, style: .continuous))
        }
    }

    private func evidenceSection(toolName: String) -> some View {
        ReviewSection(title: "Evidence") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Text("$")
                        .font(.dsMonoPt(13, weight: .semibold))
                        .foregroundStyle(t.accent)
                    Text(args ?? command ?? toolName)
                        .font(.dsMonoPt(13))
                        .foregroundStyle(t.text)
                        .lineLimit(10)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(t.surfaceSunk, in: RoundedRectangle(cornerRadius: t.r3, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                        .strokeBorder(t.border.opacity(0.6), lineWidth: 1)
                )

                Text("The daemon paused this run because this action matched your approval policy.")
                    .font(.dsSansPt(12.5))
                    .foregroundStyle(t.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var decisionBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                if let onDeny {
                    DSButton("Deny", variant: .destructive, size: .md, mono: true, fullWidth: true, action: onDeny)
                }
                DSButton(approveLabel, variant: .primary, size: .md, mono: true, fullWidth: true) {
                    onApprove?()
                }
                .disabled(requiresEvidenceConfirmation && !evidenceConfirmed)
            }
            if let onEditAndRun {
                DSButton("Edit & run", variant: .quiet, size: .md, mono: true, fullWidth: true, action: onEditAndRun)
            }
            if let onAllowAlways {
                DSButton("Allow always...", variant: .quiet, size: .md, mono: true, fullWidth: true, action: onAllowAlways)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .background(t.bg.opacity(0.98))
        .overlay(Rectangle().fill(t.border).frame(height: 1), alignment: .top)
    }

    // MARK: - Helpers

    private var evidenceCheckToggle: some View {
        HStack(spacing: 10) {
            Image(systemName: evidenceConfirmed ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20))
                .foregroundStyle(evidenceConfirmed ? t.ok : t.border)
            Text("I've reviewed the evidence")
                .font(.dsSansPt(14, weight: .medium))
                .foregroundStyle(evidenceConfirmed ? t.text : t.text3)
            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) { evidenceConfirmed = true }
        }
        .accessibilityLabel("Mark evidence as reviewed")
        .accessibilityAddTraits(.isButton)
    }

    /// cwd with the home prefix collapsed to `~` so the context line stays short.
    private var displayCwd: String {
        cwd.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    /// Only show the collapsible Details when there's something non-redundant in it.
    private var hasExtraDetails: Bool {
        hostLabel != displayCwd
    }

    private var summaryText: String {
        if let summary, !summary.isEmpty { return summary }
        if let question, !question.isEmpty { return "Agent needs your direction" }
        if let toolName, !toolName.isEmpty { return "Review \(toolName) before the agent continues" }
        return "Review this action before the agent continues"
    }

    private var riskNarrative: String {
        switch risk {
        case Approval.Risk.low.rawValue:
            return "Low-risk actions can be approved quickly, but the request stays auditable."
        case Approval.Risk.medium.rawValue:
            return "Medium-risk actions need an evidence check before approval."
        case Approval.Risk.high.rawValue:
            return "High-risk actions can change project state. Review the evidence before approving."
        default:
            return "Critical actions may affect credentials, infrastructure, or destructive state. Approve only after reviewing the evidence."
        }
    }

    private var requiresEvidenceConfirmation: Bool {
        risk >= Approval.Risk.medium.rawValue
    }

    private var hasChoiceQuestion: Bool {
        question != nil && !(choices ?? []).isEmpty
    }

    private var approveLabel: String {
        switch risk {
        case Approval.Risk.low.rawValue: "Approve"
        case Approval.Risk.medium.rawValue: "Approve after review"
        case Approval.Risk.high.rawValue: "Approve high risk"
        default: "Approve critical"
        }
    }

    @ViewBuilder
    private func metadataRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.dsMonoPt(11))
                .foregroundStyle(t.text3)
            Spacer()
            Text(value)
                .font(.dsMonoPt(11))
                .foregroundStyle(t.text)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func riskLabel(_ risk: Int) -> String {
        switch risk {
        case 0: "low"
        case 1: "medium"
        case 2: "high"
        default: "critical"
        }
    }
}

private struct ReviewSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    @Environment(\.lancerTokens) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.dsMonoPt(10, weight: .semibold))
                .foregroundStyle(t.text4)
                .tracking(0.8)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.surface, in: RoundedRectangle(cornerRadius: t.r3, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: t.r3, style: .continuous).strokeBorder(t.border, lineWidth: 1))
    }
}

#if DEBUG
#Preview("Fixture 1 – Medium approval") {
    InboxApprovalDetail(
        agentKey: .claudeCode,
        agentName: "Claude Code",
        hostLabel: "Mac Studio",
        cwd: "~/dev/lancer-ios",
        timeLabel: "2m ago",
        summary: "Edit authentication flow in AuthView.swift",
        toolName: "str_replace_editor",
        args: "AuthView.swift",
        risk: 1,
        onDeny: {},
        onApprove: {}
    )
    .lancerTokens()
}

#Preview("Fixture 2 – Critical approval") {
    InboxApprovalDetail(
        agentKey: .claudeCode,
        agentName: "Claude Code",
        hostLabel: "Mac Studio",
        cwd: "~/dev/lancer-ios",
        timeLabel: "30s ago",
        summary: "Run database migration and clear cache",
        toolName: "bash",
        args: "npm run migrate && rm -rf node_modules/.cache",
        risk: 3,
        onDeny: {},
        onApprove: {}
    )
    .lancerTokens()
}

#Preview("Fixture 3 – Agent question with choices") {
    InboxApprovalDetail(
        agentKey: .codex,
        agentName: "Codex",
        hostLabel: "hetzner-vps-1",
        cwd: "~/project",
        timeLabel: "5m ago",
        question: "Should I use async/await or completion handlers for the new API?",
        choices: ["async/await", "Completion handlers", "Ask me later"],
        risk: 0,
        onChoose: { idx in print("Choice \(idx) selected") }
    )
    .lancerTokens()
}

#Preview("Fixture 4 – Already handled (read-only, approved)") {
    InboxApprovalDetail(
        agentKey: .claudeCode,
        agentName: "Claude Code",
        hostLabel: "Mac Studio",
        cwd: "~/dev/lancer-ios",
        timeLabel: "5m ago",
        summary: "Edit authentication flow in AuthView.swift",
        toolName: "str_replace_editor",
        args: "AuthView.swift",
        risk: 1,
        resolvedDecision: .approved
    )
    .lancerTokens()
}

#Preview("Fixture 5 – Expired (read-only)") {
    InboxApprovalDetail(
        agentKey: .claudeCode,
        agentName: "Claude Code",
        hostLabel: "Mac Studio",
        cwd: "~/dev/lancer-ios",
        timeLabel: "10m ago",
        summary: "Run migration script",
        toolName: "bash",
        args: "npm run migrate",
        risk: 2,
        resolvedDecision: .expired
    )
    .lancerTokens()
}
#endif

#endif
