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
    let toolName: String?
    let args: String?
    let command: String?
    let risk: Int
    let isCritical: Bool
    let matchedRule: String?
    let onDeny: () -> Void
    let onEditAndRun: (() -> Void)?
    let onAllowAlways: (() -> Void)?
    let onApprove: () -> Void

    @Environment(\.lancerTokens) private var t
    @State private var showDetails = false

    public init(
        agentKey: AgentKey,
        agentName: String,
        hostLabel: String,
        cwd: String,
        sessionID: String? = nil,
        timeLabel: String,
        summary: String? = nil,
        question: String? = nil,
        toolName: String? = nil,
        args: String? = nil,
        command: String? = nil,
        risk: Int,
        isCritical: Bool = false,
        matchedRule: String? = nil,
        onDeny: @escaping () -> Void,
        onEditAndRun: (() -> Void)? = nil,
        onAllowAlways: (() -> Void)? = nil,
        onApprove: @escaping () -> Void
    ) {
        self.agentKey = agentKey
        self.agentName = agentName
        self.hostLabel = hostLabel
        self.cwd = cwd
        self.sessionID = sessionID
        self.timeLabel = timeLabel
        self.summary = summary
        self.question = question
        self.toolName = toolName
        self.args = args
        self.command = command
        self.risk = risk
        self.isCritical = isCritical
        self.matchedRule = matchedRule
        self.onDeny = onDeny
        self.onEditAndRun = onEditAndRun
        self.onAllowAlways = onAllowAlways
        self.onApprove = onApprove
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header: Agent + Risk + Time
                HStack(spacing: 6) {
                    AgentIdentityBadge(agent: agentKey, label: agentName)
                    RiskBadge(risk: risk)
                    Spacer()
                    Text(timeLabel)
                        .font(.dsMonoPt(11))
                        .foregroundStyle(t.text3)
                }

                // One-glance summary: plain-language statement of what this approval
                // does (derived on-device via ApprovalSummary.derive), so the decision
                // is legible before reading the raw command/diff below.
                if let summary, !summary.isEmpty {
                    Text(summary)
                        .font(.dsSansPt(15, weight: .semibold))
                        .foregroundStyle(t.text)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Content: question or tool call
                if let question {
                    // Question block
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(t.accent)
                            .frame(width: 2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("QUESTION")
                                .font(.dsDisplayPt(9, weight: .semibold))
                                .tracking(9 * 0.12)
                                .foregroundStyle(t.accent)
                            Text(question)
                                .font(.dsMonoPt(13))
                                .foregroundStyle(t.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.leading, 11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else if let toolName {
                    // The decision content, scaled to importance: a one-line plain
                    // statement, then the COMMAND as the hero (mono, prominent), then
                    // a single context line. Risk is already in the header badge, so
                    // it's not repeated here.
                    if summary == nil {
                        Text("Wants to run \(toolName)")
                            .font(.dsSansPt(15, weight: .semibold))
                            .foregroundStyle(t.text)
                    }

                    // Command hero
                    HStack(alignment: .top, spacing: 8) {
                        Text("$")
                            .font(.dsMonoPt(13, weight: .semibold))
                            .foregroundStyle(t.accent)
                        Text(args ?? toolName)
                            .font(.dsMonoPt(13))
                            .foregroundStyle(t.text)
                            .lineLimit(8)
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

                    // One context line: where it runs (the only metadata that helps
                    // the decision). Path shortened from the home prefix.
                    Text("in \(displayCwd)")
                        .font(.dsSansPt(12.5))
                        .foregroundStyle(t.text3)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                // Everything else (host, session, policy rule) is power-user detail —
                // collapsed by default so the sheet isn't a wall of metadata.
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

                // Face ID warning for CRITICAL
                if isCritical {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.orange)
                        Text("This action requires Face ID authentication to approve.")
                            .font(.dsMonoPt(12))
                            .foregroundStyle(.orange)
                    }
                    .padding(12)
                    .background(.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                            .strokeBorder(.orange.opacity(0.3), lineWidth: 1)
                    )
                }

                // Action buttons: full decision flow
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        DSButton("Deny", variant: .destructive, size: .md, mono: true, fullWidth: true, action: onDeny)
                        DSButton("Approve", variant: .primary, size: .md, mono: true, fullWidth: true, action: onApprove)
                    }
                    if let onEditAndRun {
                        DSButton("Edit & run", variant: .quiet, size: .md, mono: true, fullWidth: true, action: onEditAndRun)
                    }
                    if let onAllowAlways {
                        DSButton("Allow always…", variant: .quiet, size: .md, mono: true, fullWidth: true, action: onAllowAlways)
                    }
                }

                if isCritical {
                    Text("Allow always applies to this exact tool, input, and path. Revoke rules in Settings.")
                        .font(.dsMonoPt(11))
                        .foregroundStyle(t.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
        }
        .background(t.bg)
    }

    // MARK: - Helpers

    /// cwd with the home prefix collapsed to `~` so the context line stays short.
    private var displayCwd: String {
        cwd.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    /// Only show the collapsible Details when there's something non-redundant in it.
    private var hasExtraDetails: Bool {
        (hostLabel != displayCwd) || (matchedRule.map { !$0.isEmpty } ?? false) || (sessionID != nil)
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

#endif
