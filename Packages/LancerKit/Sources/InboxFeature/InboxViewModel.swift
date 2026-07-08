#if os(iOS)
import Foundation
import Observation
import LancerCore
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

    open func decide(
        _ id: ApprovalID,
        decision: Approval.Decision,
        choiceIndex: Int? = nil,
        editedToolInput: String? = nil
    ) {
        guard approvals.contains(where: { $0.id == id }) else { return }
        applyDecision(id, decision: decision, choiceIndex: choiceIndex, editedToolInput: editedToolInput)
    }

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
