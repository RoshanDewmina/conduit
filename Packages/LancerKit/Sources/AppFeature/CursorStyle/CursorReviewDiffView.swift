#if os(iOS)
import SwiftUI
import LancerCore
import os

/// Governed-approval review bound to `liveBridge.pendingApproval` / `lookupApproval`.
public struct CursorReviewDiffView: View {
    @Environment(\.cursorShellLiveBridge) private var liveBridge

    private enum Decision: Equatable {
        case pending, approved, denied, replied
    }

    @State private var decision: Decision = .pending
    @State private var boundApproval: Approval?

    private let onBack: () -> Void

    public init(onBack: @escaping () -> Void = {}) {
        self.onBack = onBack
    }

    private var liveApproval: Approval? {
        guard let id = liveBridge?.pendingApprovalID else { return nil }
        if let resolved = liveBridge?.pendingApproval, resolved.id == id {
            return resolved
        }
        return liveBridge?.lookupApproval?(id)
    }

    private var approval: Approval? { boundApproval ?? liveApproval }

    private func syncBoundApproval() {
        guard let live = liveApproval else { return }
        if live.id != boundApproval?.id {
            decision = .pending
        }
        boundApproval = live
    }

    public var body: some View {
        Form {
            Section("Request") {
                Text(requestTitle)
            }
            Section("Scope") {
                LabeledContent("Agent", value: approval?.agent.rawValue ?? "—")
                LabeledContent("Kind", value: approval?.kind.rawValue ?? "—")
                LabeledContent("Directory", value: approval?.cwd.isEmpty == false ? approval!.cwd : "—")
                if let toolName = approval?.toolName, !toolName.isEmpty {
                    LabeledContent("Tool", value: toolName)
                }
                LabeledContent("Command", value: approval?.command ?? "—")
            }
            Section("Risk") {
                Text(riskLabel)
                if let blastRadius = approval?.blastRadius, let summary = blastRadiusSummary(blastRadius) {
                    Text(summary).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section("Evidence") {
                Text(approval?.command ?? approval?.toolInput ?? approval?.patch ?? "(no command recorded)")
                    .font(.system(.body, design: .monospaced))
                if let hash = approval?.contentHash, !hash.isEmpty {
                    Text("content hash \(hash.prefix(12))…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Decision") {
                if decision == .pending {
                    Button("Approve") { applyDecision(.approved, relay: .approved) }
                        .accessibilityIdentifier("cursor.review.approve")
                    Button("Deny", role: .destructive) { applyDecision(.denied, relay: .rejected) }
                    Button("Reply") { applyDecision(.replied, relay: nil) }
                } else {
                    Text(decisionLabel)
                }
            }
            if decision != .pending {
                Section {
                    Text(auditText).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Review")
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Back", systemImage: "chevron.left", action: onBack)
            }
        }
        // Expose as an accessibility container so UITests can find `review-diff-screen`
        // even when Form children dominate the tree.
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

    private var requestTitle: String {
        guard let approval else { return "No pending approval" }
        if approval.kind == .askQuestion, let question = approval.question, !question.isEmpty {
            return question
        }
        return approval.command ?? approval.patch ?? "\(approval.kind.rawValue) request"
    }

    private var riskLabel: String {
        switch approval?.risk {
        case .critical: return "Critical risk"
        case .high: return "High risk"
        case .medium: return "Medium risk"
        case .low, .none: return "Low risk"
        }
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
        return parts.joined(separator: " · ")
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

    private var decisionLabel: String {
        switch decision {
        case .approved: return "Approved"
        case .denied: return "Denied"
        case .replied: return "Reply sent"
        case .pending: return ""
        }
    }

    private var auditText: String {
        switch decision {
        case .approved, .denied: return "Decided by You · just now"
        case .replied: return "Replied by You · just now"
        case .pending: return ""
        }
    }
}
#endif
