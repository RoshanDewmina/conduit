#if os(iOS)
import Foundation
import Observation
import LancerCore
import SecurityKit
import DesignSystem

@MainActor @Observable
open class InboxViewModel {
    public var approvals: [Approval] = []

    public var effectiveApprovals: [Approval] { approvals }

    /// Optional sink fired after a decision mutates a pending row. The base VM only
    /// mutates local state; the relay/default inbox sets this to forward the decision
    /// to the daemon (LiveInboxViewModel has its own repository-backed onDecision).
    /// The 4th param is the resolved approval's `contentHash`, echoed back so
    /// lancerd's `approvalStore.resolve` can verify the decision was made on the
    /// exact content shown — `nil` for approvals that never carried one.
    public var decisionSink: ((ApprovalID, Approval.Decision, String?, String?) -> Void)?

    public init(approvals: [Approval] = []) {
        self.approvals = approvals
    }

    /// Local-auth hook run before a high/critical-risk decision commits
    /// (`ApprovalDecisionAuth.requiresUnlock` tiers). Injectable so tests can
    /// assert the blocked/allowed behaviour without real LocalAuthentication.
    public var decisionAuthorizer: (Approval.Risk?) async -> Bool = {
        await ApprovalDecisionAuth.authorize(risk: $0)
    }

    open func decide(
        _ id: ApprovalID,
        decision: Approval.Decision,
        choiceIndex: Int? = nil,
        editedToolInput: String? = nil
    ) {
        guard let idx = approvals.firstIndex(where: { $0.id == id }) else { return }
        let risk = approvals[idx].risk
        if ApprovalDecisionAuth.requiresUnlock(risk: risk) {
            Task {
                guard await decisionAuthorizer(risk) else { return }
                applyDecision(id, decision: decision, choiceIndex: choiceIndex, editedToolInput: editedToolInput)
            }
        } else {
            applyDecision(id, decision: decision, choiceIndex: choiceIndex, editedToolInput: editedToolInput)
        }
    }

    /// Applies a decision that has already passed the local-auth gate. Never
    /// call directly from a user-action path — `decide` is the gated entry.
    func applyDecision(
        _ id: ApprovalID,
        decision: Approval.Decision,
        choiceIndex: Int? = nil,
        editedToolInput: String? = nil
    ) {
        if let idx = approvals.firstIndex(where: { $0.id == id }) {
            let contentHash = approvals[idx].contentHash
            approvals[idx].decision = decision
            approvals[idx].decidedAt = .now
            if let ci = choiceIndex { approvals[idx].answeredChoice = ci }
            if let edited = editedToolInput, !edited.isEmpty {
                approvals[idx].toolInput = edited
            }
            if decision == .approvedAlways {
                persistAllowAlwaysRule(for: approvals[idx])
            }
            Haptics.selection()
            decisionSink?(id, decision, editedToolInput, contentHash)
        }
    }
}

func persistAllowAlwaysRule(for approval: Approval) {
    let key = "inbox.allowAlwaysRules"
    var rules: [[String: String]] = (UserDefaults.standard.array(forKey: key) as? [[String: String]]) ?? []
    let entry: [String: String] = [
        "command": approval.command ?? "",
        "toolName": approval.toolName ?? "",
        "cwd": approval.cwd,
        "risk": String(approval.risk.rawValue),
        "agent": String(describing: approval.agent),
    ]
    rules.append(entry)
    UserDefaults.standard.set(rules, forKey: key)
}
#endif
