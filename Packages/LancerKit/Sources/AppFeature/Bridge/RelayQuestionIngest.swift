#if os(iOS)
import Foundation
import Observation
import LancerCore
import PersistenceKit
import SessionFeature

/// In-thread questions: the missing link between `E2ERelayBridge.handleRelayMessage`'s
/// `"questionPending"` case (`Packages/LancerKit/Sources/SessionFeature/E2ERelayBridge.swift`)
/// — which already posts a `lancerE2EQuestionPending` `NotificationCenter` notification
/// for every incoming relay question — and the rest of the app. Before this type,
/// nothing subscribed to that notification at all; it was posted into the void,
/// the exact same shape of gap M4 found and closed for approvals
/// (`lancerE2EApprovalReceived` → `RelayApprovalIngest`).
///
/// Unlike `E2ERelayMessage.ApprovalData`, `QuestionPendingParams` carries an optional
/// `runId` — a relay-delivered question CAN be correlated to the specific local turn
/// it belongs to. When that correlation succeeds, this type persists a real `.question`
/// `ChatArtifact` (same shape `ChatRunPersistenceSink.handleQuestionPending` already
/// defines for the SSH-only path) so the answered state survives app relaunch — a
/// strictly better outcome than the approval card gets today. `QuestionCardModel.decode`
/// is reused either way (persisted-or-synthetic artifact) so decode logic is never
/// duplicated.
///
/// SCOPE LIMITATION (deliberate, mirrors `RelayApprovalIngest`): `latestPendingQuestion`
/// is keyed by `RelayMachineID`, not by run/conversation. `LiveThreadView` only ever
/// talks to one active machine at a time, so machine-scoped is sufficient for this UI
/// even though the wire data would support run-level precision. Multiple simultaneous
/// pending questions on the same machine are not queued — a newer question replaces the
/// older one, same simplification `RelayApprovalIngest` made for approvals.
@MainActor
@Observable
public final class RelayQuestionIngest {
    /// The most recently ingested pending question per machine. `LiveThreadView` looks
    /// this up by `ShellLiveBridge.activeMachineID`.
    public private(set) var latestPendingQuestion: [RelayMachineID: QuestionCardModel.PresentationState] = [:]

    /// The persisted artifact id for a pending question, when a local turn correlation
    /// succeeded (`runId` was present and matched a known turn) — used by `submit` to
    /// merge the answer back into the artifact's payload. Absent for questions that
    /// couldn't be correlated to a local turn (still rendered/answerable, just not
    /// durably persisted).
    private var persistedArtifactID: [RelayMachineID: String] = [:]

    private let chatRepo: ChatConversationRepository
    private var listenTask: Task<Void, Never>?

    /// Optional sink for CursorStyle — when set, every publish/clear of
    /// `latestPendingQuestion` is forwarded so `CursorShellLiveBridge` can
    /// mirror the pending card + `hasBlockingQuestion` attention without
    /// duplicating decode logic.
    public var onPendingChanged: (@MainActor (RelayMachineID, QuestionCardModel.PresentationState?) -> Void)?

    public init(chatRepo: ChatConversationRepository) {
        self.chatRepo = chatRepo
    }

    /// Starts observing `lancerE2EQuestionPending`. Idempotent, same convention as
    /// `RelayApprovalIngest.start()`.
    public func start() {
        guard listenTask == nil else { return }
        listenTask = Task { [weak self] in
            for await notification in NotificationCenter.default.notifications(
                named: Notification.Name("lancerE2EQuestionPending")
            ) {
                guard let self else { return }
                await self.handle(notification)
            }
        }
    }

    private func handle(_ notification: Notification) async {
        guard
            let wire = notification.userInfo?["questionData"] as? E2ERelayMessage.QuestionData,
            let machineID = notification.userInfo?["machineID"] as? RelayMachineID
        else { return }

        // 30a28e26 wire fix: relay `QuestionData` is keyed `questionID`, not
        // SSH `id` — shared conversion lives in `CursorQuestionCardModel`.
        let params = CursorQuestionCardModel.pendingParams(from: wire)

        guard let payloadData = try? JSONEncoder().encode(QuestionArtifactPayload(event: params)),
              let payloadJSON = String(data: payloadData, encoding: .utf8)
        else { return }

        var turn: LancerCore.ChatTurn?
        if let runID = params.runId, !runID.isEmpty {
            turn = try? await chatRepo.turnByRunID(runID)
        }

        let artifact = ChatArtifact(
            id: "question:\(params.id)",
            conversationID: turn?.conversationID ?? "",
            turnID: turn?.id ?? "",
            runID: params.runId ?? "",
            kind: .question,
            title: "Question",
            payloadJSON: payloadJSON,
            status: .running
        )

        if turn != nil {
            try? await chatRepo.upsertArtifact(artifact)
            persistedArtifactID[machineID] = artifact.id
        } else {
            persistedArtifactID[machineID] = nil
        }

        guard let state = QuestionCardModel.decode(from: artifact) else { return }
        latestPendingQuestion[machineID] = state
        onPendingChanged?(machineID, state)
    }

    /// Toggle an option in the currently-published question for `machineID` — forwards
    /// to `QuestionCardModel.toggleOption` against the published dict's entry in place.
    public func toggleOption(machineID: RelayMachineID, itemIndex: Int, label: String) {
        guard var state = latestPendingQuestion[machineID] else { return }
        QuestionCardModel.toggleOption(in: &state, itemIndex: itemIndex, label: label)
        latestPendingQuestion[machineID] = state
        onPendingChanged?(machineID, state)
    }

    /// Update the free-text field for the currently-published question for `machineID`.
    public func setFreeText(machineID: RelayMachineID, itemIndex: Int, text: String) {
        guard var state = latestPendingQuestion[machineID] else { return }
        QuestionCardModel.setFreeText(in: &state, itemIndex: itemIndex, text: text)
        latestPendingQuestion[machineID] = state
        onPendingChanged?(machineID, state)
    }

    /// Entry point for the in-thread Submit button. Builds the wire answer, sends it
    /// directly over the originating machine's relay bridge (mirrors
    /// `RelayApprovalIngest.decide`'s direct-bridge-call pattern, not
    /// `CommandGateway.answerQuestion`'s AppIntent-oriented "any connected machine"
    /// fallback — a live thread already knows its exact machine). Best-effort persists
    /// the answered state into the artifact this question was ingested against, if any
    /// (matching `CommandGateway.persistAnsweredQuestion`'s "daemon already has it, the
    /// local mirror is best-effort" reasoning). Clears the published card regardless of
    /// persistence success, since the daemon send is the actual source of truth.
    @discardableResult
    public func submit(machineID: RelayMachineID, relayFleetStore: RelayFleetStore) async -> Bool {
        guard let state = latestPendingQuestion[machineID],
              QuestionCardModel.isReadyToAnswer(state)
        else { return false }

        let answer = QuestionCardModel.buildAnswer(from: state)
        guard let bridge = relayFleetStore.machine(machineID)?.bridge else { return false }
        let sent = await bridge.sendQuestionAnswer(answer)

        if let artifactID = persistedArtifactID[machineID],
           let artifact = try? await chatRepo.artifact(id: artifactID),
           let mergedJSON = QuestionCardModel.mergeAnswer(into: artifact.payloadJSON, answer: answer) {
            var updated = artifact
            updated.payloadJSON = mergedJSON
            updated.status = .done
            try? await chatRepo.upsertArtifact(updated)
        }

        latestPendingQuestion[machineID] = nil
        persistedArtifactID[machineID] = nil
        onPendingChanged?(machineID, nil)
        return sent
    }
}
#endif
