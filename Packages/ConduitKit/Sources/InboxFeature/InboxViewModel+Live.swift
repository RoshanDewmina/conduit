#if os(iOS)
import SwiftUI
import Observation
import ConduitCore
import PersistenceKit

@MainActor @Observable
public final class LiveInboxViewModel: InboxViewModel {
    private let repository: ApprovalRepository
    private let onDecision: (@Sendable (ApprovalID, Approval.Decision) async -> Void)?
    @ObservationIgnored nonisolated(unsafe) private var observationTask: Task<Void, Never>?

    public init(
        repository: ApprovalRepository,
        onDecision: (@Sendable (ApprovalID, Approval.Decision) async -> Void)? = nil
    ) {
        self.repository = repository
        self.onDecision = onDecision
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
                }
            } catch { /* observation ended */ }
        }
    }

    override public func decide(_ id: ApprovalID, decision: Approval.Decision) {
        super.decide(id, decision: decision)  // updates in-memory immediately
        Task {
            try? await repository.decide(id: id, decision: decision)
            await onDecision?(id, decision)
        }
    }

    deinit {
        observationTask?.cancel()
    }
}
#endif
