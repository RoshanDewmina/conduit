#if os(iOS)
import Observation
import LancerCore
import PersistenceKit
import NotificationsKit
import SecurityKit

@MainActor @Observable
public final class LiveInboxViewModel: InboxViewModel {
    private let repository: ApprovalRepository
    /// The 4th param is the resolved approval's `contentHash` (nil if the row
    /// never carried one) — see `InboxViewModel.decisionSink`'s doc comment.
    private let onDecision: (@Sendable (ApprovalID, Approval.Decision, String?, String?) async -> Void)?
    private let onPendingApprovalsChanged: (@Sendable (Int, String?, String?) async -> Void)?
    @ObservationIgnored nonisolated(unsafe) private var observationTask: Task<Void, Never>?

    public init(
        repository: ApprovalRepository,
        onDecision: (@Sendable (ApprovalID, Approval.Decision, String?, String?) async -> Void)? = nil,
        onPendingApprovalsChanged: (@Sendable (Int, String?, String?) async -> Void)? = nil
    ) {
        self.repository = repository
        self.onDecision = onDecision
        self.onPendingApprovalsChanged = onPendingApprovalsChanged
        super.init()
        startObserving()
    }

    private func startObserving() {
        observationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                for try await approvals in await self.repository.observe() {
                    guard !Task.isCancelled else { break }
                    self.approvals = approvals
                    let pending = approvals.filter(\.isPending)
                    await self.onPendingApprovalsChanged?(
                        pending.count,
                        pending.first.map(Self.agentLabel(for:)),
                        pending.first?.id.uuidString
                    )
                }
            } catch { /* observation ended */ }
        }
    }

    override public func decide(
        _ id: ApprovalID,
        decision: Approval.Decision,
        choiceIndex: Int? = nil,
        editedToolInput: String? = nil
    ) {
        // First-decision-wins: ignore a tap on an already-resolved gate (stale
        // row still visible, or a double-tap) so we never flip a decided
        // approval or double-send to lancerd.
        let existing = approvals.first(where: { $0.id == id })
        if let existing, !existing.isPending {
            return
        }
        let contentHash = existing?.contentHash
        // Gate BEFORE any mutation or persistence: a high/critical (or
        // unknown-risk — `existing` can be nil when the row hasn't loaded into
        // memory yet) decision needs a fresh local-auth unlock, and both the
        // in-memory flip and the DB write must wait for it. The base class's
        // `decide` gates independently, so route the post-auth work through the
        // ungated `applyDecision` to avoid a second prompt.
        let risk = existing?.risk
        Task {
            if ApprovalDecisionAuth.requiresUnlock(risk: risk) {
                guard await decisionAuthorizer(risk) else { return }
            }
            applyDecision(id, decision: decision, choiceIndex: choiceIndex, editedToolInput: editedToolInput)
            // The DB UPDATE is guarded on `decision IS NULL`; only forward to the
            // wire + clear the lock-screen banner when this call actually resolved
            // the row. The Live Activity / badge update follows reactively from the
            // `observe()` re-emit that this write triggers.
            let changed = (try? await repository.decide(id: id, decision: decision)) ?? false
            guard changed else { return }
            Notifications.shared.clearDeliveredApproval(id: id.uuidString)
            await onDecision?(id, decision, editedToolInput, contentHash)
        }
    }

    deinit {
        observationTask?.cancel()
    }

    private static func agentLabel(for approval: Approval) -> String {
        switch approval.agent {
        case .claudeCode: "Claude Code"
        case .codex:      "Codex"
        case .cursor:     "Cursor"
        case .opencode:   "OpenCode"
        case .devin:      "Devin"
        case .unknown:    "Agent"
        }
    }
}
#endif
